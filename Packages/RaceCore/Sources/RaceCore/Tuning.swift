public struct Tuning: Codable, Equatable, Sendable {
    public var gravity = 20.0
    public var slopeGravityFactor = 0.35
    public var gasAccel = 8.0
    public var boostAccel = 18.0
    public var normalTopSpeed = 19.0
    public var boostTopSpeed = 29.0
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
    public var laneChangeTime = 0.25          // seconds to cross one lane
    public var bikeLength = 1.8               // metres; closer than this in one lane is contact
    public var laneBumpSpeedFactor = 0.9      // speed kept by a bike whose lane change is refused
    public var laneBumpCooldown = 0.3
    public var mudTopSpeed = 9.0
    public var mudDecel = 40.0
    public var boostPadSpeed = 32.0

    public init() {}
}
