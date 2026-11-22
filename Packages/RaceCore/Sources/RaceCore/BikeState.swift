import Foundation

public enum BikePhase: Equatable, Sendable { case grounded, airborne, crashed(remaining: Double) }

public struct BikeState: Equatable, Sendable {
    public var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    public var angle = 0.0                    // radians, positive = nose up
    public var heat = 0.0                     // 0...1
    public var stallRemaining = 0.0           // seconds; > 0 means engine cut out
    public var phase = BikePhase.grounded
    public var finished = false
    /// Seconds from the start to crossing the finish line.
    public var finishTime: Double?
    /// 0 is the far lane (drawn highest), `Track.laneCount - 1` the near one; fractional while changing.
    public var lane = 1.0
    public var targetLane = 1
    /// Seconds before another lane change is accepted after one was refused.
    public var laneCooldown = 0.0

    public var speed: Double { hypot(vx, vy) }

    public init() {}
}
