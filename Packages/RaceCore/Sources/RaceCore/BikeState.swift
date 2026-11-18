import Foundation

public enum BikePhase: Equatable, Sendable { case grounded, airborne, crashed(remaining: Double) }

public struct BikeState: Equatable, Sendable {
    public var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    public var angle = 0.0                    // radians, positive = nose up
    public var heat = 0.0                     // 0...1
    public var stallRemaining = 0.0           // seconds; > 0 means engine cut out
    public var phase = BikePhase.grounded
    public var finished = false

    public var speed: Double { hypot(vx, vy) }

    public init() {}
}
