public struct Tuning: Codable, Equatable, Sendable {
    public var gravity = 20.0
    public var slopeGravityFactor = 0.35
    public var gasAccel = 8.0
    public var boostAccel = 12.0
    public var normalTopSpeed = 16.0
    public var boostTopSpeed = 24.0
    public var coastDecel = 3.0
    public var minTakeoffSpeed = 4.0          // below this a grounded bike always follows the terrain
    public var leanRate = 2.5
    public var cleanLandingAngle = 0.26
    public var crashLandingAngle = 0.79
    public var sloppyLandingSpeedFactor = 0.6
    public var crashDuration = 2.0
    public var stallDuration = 3.0
    public var heatFillTime = 4.0
    public var heatDrainTime = 6.0

    public init() {}
}
