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
        let input = bike.finished ? RiderInput() : rawInput
        if !bike.finished { time += Race.dt }
        // Engine running: not stalled and not finished. Boost implies gas.
        let running = bike.stallRemaining == 0 && !bike.finished
        let boosting = running && input.boost
        let gas = running && (input.gas || input.boost)
        if bike.phase == .grounded { stepGrounded(gas: gas, boost: boosting) }
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
        bike.x += speed * cos(slope) * Race.dt
        Race.snapToTerrain(&bike, terrain: terrain, speed: speed)
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
