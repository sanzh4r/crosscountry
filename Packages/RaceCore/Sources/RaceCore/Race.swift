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
        if bike.phase == .grounded { stepGrounded(input) }
        if bike.x >= terrain.finishX { bike.finished = true }
    }

    // MARK: Grounded riding

    private mutating func stepGrounded(_ input: RiderInput) {
        let slope = terrain.slope(at: bike.x)
        var speed = bike.speed
        speed = throttled(speed, gas: input.gas)
        speed -= tuning.gravity * tuning.slopeGravityFactor * sin(slope) * Race.dt
        speed = max(0, speed)
        bike.x += speed * cos(slope) * Race.dt
        Race.snapToTerrain(&bike, terrain: terrain, speed: speed)
    }

    /// Accelerates toward the top speed under gas; otherwise coasts down.
    private func throttled(_ speed: Double, gas: Bool) -> Double {
        let top = tuning.normalTopSpeed
        if gas {
            if speed < top { return min(speed + tuning.gasAccel * Race.dt, top) }
            return max(speed - tuning.coastDecel * Race.dt, top)
        }
        return max(speed - tuning.coastDecel * Race.dt, 0)
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
