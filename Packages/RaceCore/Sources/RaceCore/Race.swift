import Foundation

public struct Race: Sendable {
    public static let dt = 1.0 / 60.0

    /// Start grid: the front row sits two cells in, the back row this far behind it.
    static let gridRowGap = 2.5
    /// Lanes on the grid for the player and then each rival; the fourth bike starts in the back row.
    private static let gridLanes = [1, 0, 2, 0]

    public let track: Track
    public let terrain: Terrain
    public var tuning: Tuning
    /// Every bike in the race; the player is first, rivals follow.
    public private(set) var bikes: [BikeState]
    /// The player's race time; stops advancing once the player has finished.
    public private(set) var time: Double
    /// Seconds since the start for everyone; keeps running after the player finishes.
    private var clock = 0.0
    private let surfaces: [PlacedPiece]

    /// The player's bike.
    public var bike: BikeState { bikes[0] }

    /// `bike` replaces the player's start state (tests); `rivals` adds that many bikes to the grid.
    public init(track: Track, tuning: Tuning = Tuning(), bike: BikeState? = nil, rivals: Int = 0) {
        self.track = track
        self.terrain = Terrain(track: track)
        self.tuning = tuning
        self.surfaces = track.pieces.filter { !$0.kind.isTerrain }
        var grid: [BikeState] = []
        for i in 0...max(rivals, 0) {
            var b = BikeState()
            let lane = Race.gridLanes[i % Race.gridLanes.count]
            b.x = 2 * Track.cellWidth - Double(i / Track.laneCount) * Race.gridRowGap
            b.lane = Double(lane)
            b.targetLane = lane
            if i == 0, let bike { b = bike }
            if b.phase == .grounded { Race.snapToTerrain(&b, terrain: terrain) }
            grid.append(b)
        }
        self.bikes = grid
        self.time = 0
    }

    /// Steps a race with only the player riding; any rivals get no input.
    public mutating func step(_ input: RiderInput) { step([input]) }

    /// One step for every bike; `inputs[i]` drives `bikes[i]`, missing entries mean no input.
    public mutating func step(_ inputs: [RiderInput]) {
        clock += Race.dt
        if !bikes[0].finished { time += Race.dt }
        for i in bikes.indices {
            let raw = i < inputs.count ? inputs[i] : RiderInput()
            requestLaneChange(i, raw.laneChange)
            var b = bikes[i]
            advance(&b, raw)
            if b.finished && b.finishTime == nil { b.finishTime = clock }
            bikes[i] = b
        }
        resolveRearContacts()
    }

    /// Place in the race, 1 = leading. Finished bikes rank by finish time, the rest by distance.
    public func position(of index: Int) -> Int {
        let me = bikes[index]
        var ahead = 0
        for (i, other) in bikes.enumerated() where i != index {
            switch (me.finishTime, other.finishTime) {
            case let (mine?, theirs?): if theirs < mine || (theirs == mine && i < index) { ahead += 1 }
            case (nil, _?): ahead += 1
            case (_?, nil): break
            case (nil, nil): if other.x > me.x || (other.x == me.x && i < index) { ahead += 1 }
            }
        }
        return ahead + 1
    }

    /// The surface piece (mud or boost pad) under `x` in `lane`, if any.
    public func surface(at x: Double, lane: Int) -> PieceKind? {
        let cell = Int((x / Track.cellWidth).rounded(.down))
        return surfaces.first { $0.lane == lane && cell >= $0.cell && cell < $0.cell + $0.kind.widthCells }?.kind
    }

    private func advance(_ bike: inout BikeState, _ rawInput: RiderInput) {
        let crashed = if case .crashed = bike.phase { true } else { false }
        let input = bike.finished || crashed ? RiderInput() : rawInput
        // Engine running: not stalled and not finished. Boost implies gas.
        let running = bike.stallRemaining == 0 && !bike.finished
        let boosting = running && input.boost
        let gas = running && (input.gas || input.boost)
        switch bike.phase {
        case .grounded: stepGrounded(&bike, gas: gas, boost: boosting)
        case .airborne: stepAirborne(&bike, lean: input.lean)
        case .crashed(let remaining): stepCrashed(&bike, remaining: remaining)
        }
        updateHeatAndStall(&bike, boosting: boosting)
        stepLane(&bike)
        if bike.x >= terrain.finishX { bike.finished = true }
    }

    // MARK: Lanes and contact

    /// A bike not already changing lane starts moving one lane over. If another bike is in the way
    /// the move is refused and the mover loses a little speed.
    private mutating func requestLaneChange(_ index: Int, _ direction: Int) {
        var b = bikes[index]
        if case .crashed = b.phase { return }
        guard direction != 0, !b.finished, b.laneCooldown == 0, b.lane == Double(b.targetLane) else { return }
        let wanted = b.targetLane + (direction > 0 ? 1 : -1)
        guard (0..<Track.laneCount).contains(wanted) else { return }
        let blocked = bikes.enumerated().contains { j, other in
            if j == index { return false }
            if case .crashed = other.phase { return false }
            return abs(other.x - b.x) < tuning.bikeLength
                && (other.targetLane == wanted || abs(other.lane - Double(wanted)) < 0.5)
        }
        if blocked {
            Race.scaleSpeed(&b, tuning.laneBumpSpeedFactor)
            b.laneCooldown = tuning.laneBumpCooldown
        } else {
            b.targetLane = wanted
        }
        bikes[index] = b
    }

    private func stepLane(_ bike: inout BikeState) {
        bike.laneCooldown = max(0, bike.laneCooldown - Race.dt)
        let target = Double(bike.targetLane)
        let move = Race.dt / max(tuning.laneChangeTime, Race.dt)
        bike.lane = bike.lane < target ? min(bike.lane + move, target) : max(bike.lane - move, target)
    }

    /// A bike on the ground that runs into the back of another in its lane is held to that bike's speed.
    private mutating func resolveRearContacts() {
        guard bikes.count > 1 else { return }
        for i in bikes.indices where bikes[i].phase == .grounded {
            for j in bikes.indices where j != i && bikes[j].phase == .grounded {
                let gap = bikes[j].x - bikes[i].x
                guard gap > 0, gap < tuning.bikeLength, abs(bikes[j].lane - bikes[i].lane) < 0.5 else { continue }
                let mine = bikes[i].speed, theirs = bikes[j].speed
                if mine > theirs { Race.scaleSpeed(&bikes[i], mine > 0 ? theirs / mine : 0) }
            }
        }
    }

    private static func scaleSpeed(_ bike: inout BikeState, _ factor: Double) {
        bike.vx *= factor
        bike.vy *= factor
    }

    // MARK: Grounded riding

    private func stepGrounded(_ bike: inout BikeState, gas: Bool, boost: Bool) {
        let slope = terrain.slope(at: bike.x)
        var speed = bike.speed
        speed = throttled(speed, gas: gas, boost: boost)
        switch surface(at: bike.x, lane: Int(bike.lane.rounded())) {
        case .mud: if speed > tuning.mudTopSpeed { speed = max(tuning.mudTopSpeed, speed - tuning.mudDecel * Race.dt) }
        case .boostPad: speed = max(speed, tuning.boostPadSpeed)
        default: break
        }
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
    private func stepAirborne(_ bike: inout BikeState, lean: Double) {
        let dt = Race.dt
        bike.x += bike.vx * dt
        bike.y += bike.vy * dt - 0.5 * tuning.gravity * dt * dt
        bike.vy -= tuning.gravity * dt
        bike.angle -= min(max(lean, -1), 1) * tuning.leanRate * dt
        if bike.y <= terrain.height(at: bike.x) { land(&bike) }
    }

    /// Grades the landing by how far the bike's angle is from the slope: clean keeps the
    /// along-slope speed, sloppy loses some, anything worse crashes.
    private func land(_ bike: inout BikeState) {
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
    private func stepCrashed(_ bike: inout BikeState, remaining: Double) {
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
    private func updateHeatAndStall(_ bike: inout BikeState, boosting: Bool) {
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
