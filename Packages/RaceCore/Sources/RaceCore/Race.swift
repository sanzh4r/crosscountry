import Foundation

public struct Race: Sendable {
    public static let dt = 1.0 / 60.0

    public let terrain: Terrain
    public var tuning: Tuning
    public private(set) var bike: BikeState
    public private(set) var time: Double      // stops advancing once bike.finished

    public init(track: Track, tuning: Tuning = Tuning(), bike: BikeState? = nil) {
        self.terrain = Terrain(track: track)
        self.tuning = tuning
        var start = bike ?? {
            var b = BikeState()
            b.x = 2 * Track.cellWidth
            return b
        }()
        if start.phase == .grounded { Race.snapToTerrain(&start, terrain: terrain) }
        self.bike = start
        self.time = 0
    }

    public mutating func step(_ rawInput: RiderInput) {
        let crashed = if case .crashed = bike.phase { true } else { false }
        let input = bike.finished || crashed ? RiderInput() : rawInput
        if !bike.finished { time += Race.dt }
        // Engine running: not stalled and not finished. Boost implies gas.
        let running = bike.stallRemaining == 0 && !bike.finished
        let boosting = running && input.boost
        let gas = running && (input.gas || input.boost)
        switch bike.phase {
        case .grounded: stepGrounded(gas: gas, boost: boosting)
        case .airborne: stepAirborne(lean: input.lean)
        case .crashed(let remaining): stepCrashed(remaining: remaining)
        }
        updateHeatAndStall(boosting: boosting)
        if bike.x >= terrain.finishX { bike.finished = true }
    }

    // MARK: Grounded riding

    private mutating func stepGrounded(gas: Bool, boost: Bool) {
        let slope = terrain.slope(at: bike.x)
        var speed = bike.speed
        speed = throttled(speed, gas: gas, boost: boost)
        speed -= tuning.gravity * tuning.slopeGravityFactor * sin(slope) * Race.dt
        speed = max(0, speed)
        // Ballistic candidate from the velocity along the current slope; take off if it clears the ground
        // and the bike is fast enough (a slow bike rolls over sharp crests instead of hopping off them).
        let dt = Race.dt
        let vx = speed * cos(slope), vy = speed * sin(slope)
        let x = bike.x + vx * dt
        let y = bike.y + vy * dt - 0.5 * tuning.gravity * dt * dt
        if speed >= tuning.minTakeoffSpeed && y > terrain.height(at: x) + 1e-6 {
            bike.x = x
            bike.y = y
            bike.vx = vx
            bike.vy = vy - tuning.gravity * dt
            bike.phase = .airborne
            return
        }
        bike.x = x
        Race.snapToTerrain(&bike, terrain: terrain, speed: speed)
    }

    // MARK: Airborne and landing

    /// Ballistic flight; lean rotates the bike (positive lean = nose down). Gas and boost do nothing here.
    private mutating func stepAirborne(lean: Double) {
        let dt = Race.dt
        bike.x += bike.vx * dt
        bike.y += bike.vy * dt - 0.5 * tuning.gravity * dt * dt
        bike.vy -= tuning.gravity * dt
        bike.angle -= min(max(lean, -1), 1) * tuning.leanRate * dt
        if bike.y <= terrain.height(at: bike.x) { land() }
    }

    /// Grades the landing by how far the bike's angle is from the slope: clean keeps the
    /// along-slope speed, sloppy loses some, anything worse crashes.
    private mutating func land() {
        let slope = terrain.slope(at: bike.x)
        let d = abs((bike.angle - slope).remainder(dividingBy: 2 * .pi))
        let s = max(0, bike.vx * cos(slope) + bike.vy * sin(slope))
        if d <= tuning.cleanLandingAngle {
            Race.snapToTerrain(&bike, terrain: terrain, speed: s)
            bike.phase = .grounded
        } else if d <= tuning.crashLandingAngle {
            Race.snapToTerrain(&bike, terrain: terrain, speed: s * tuning.sloppyLandingSpeedFactor)
            bike.phase = .grounded
        } else {
            bike.y = terrain.height(at: bike.x)
            bike.vx = 0
            bike.vy = 0
            bike.phase = .crashed(remaining: tuning.crashDuration)
        }
    }

    // MARK: Crashed

    /// Position is fixed while the timer runs; on expiry the bike is back on the ground, stopped.
    private mutating func stepCrashed(remaining: Double) {
        let left = max(0, remaining - Race.dt)
        if left > 0 {
            bike.phase = .crashed(remaining: left)
            return
        }
        Race.snapToTerrain(&bike, terrain: terrain)
        bike.phase = .grounded
    }

    /// Accelerates toward the top speed under gas (boost raises both accel and top speed);
    /// above the top speed, or without gas, the bike coasts down.
    private func throttled(_ speed: Double, gas: Bool, boost: Bool) -> Double {
        let top = boost ? tuning.boostTopSpeed : tuning.normalTopSpeed
        let accel = boost ? tuning.boostAccel : tuning.gasAccel
        if gas {
            if speed < top { return min(speed + accel * Race.dt, top) }
            return max(speed - tuning.coastDecel * Race.dt, top)
        }
        return max(speed - tuning.coastDecel * Race.dt, 0)
    }

    // MARK: Heat and stall

    /// Runs every step in every phase. Boosting fills heat; reaching 1 stalls the engine
    /// (timer starts counting down on the following step). Otherwise heat drains.
    private mutating func updateHeatAndStall(boosting: Bool) {
        if bike.stallRemaining > 0 {
            bike.stallRemaining = max(0, bike.stallRemaining - Race.dt)
            bike.heat = 0
        } else if boosting {
            bike.heat += Race.dt / tuning.heatFillTime
            if bike.heat >= 1 {
                bike.stallRemaining = tuning.stallDuration
                bike.heat = 0
            }
        } else {
            bike.heat = max(0, bike.heat - Race.dt / tuning.heatDrainTime)
        }
    }

    /// Places the bike on the terrain at its x, aligned to the slope, moving at `speed` along it.
    private static func snapToTerrain(_ bike: inout BikeState, terrain: Terrain, speed: Double = 0) {
        let slope = terrain.slope(at: bike.x)
        bike.y = terrain.height(at: bike.x)
        bike.angle = slope
        bike.vx = speed * cos(slope)
        bike.vy = speed * sin(slope)
    }
}
