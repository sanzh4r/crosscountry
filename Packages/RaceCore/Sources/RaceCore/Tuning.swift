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
    public var wheelieRate = 1.0              // rad/s the front wheel rises while leaning back with gas
    public var wheelieDropRate = 3.0          // rad/s it falls when let go
    public var wheeliePushDownRate = 6.0      // rad/s it falls when leaning forward
    public var wheelieFlipAngle = 1.15        // lifted this far, the bike goes over backwards
    public var wheelieFloatAngle = 0.3        // lifted at least this far, mud does not slow the bike
    public var wheelieMinSpeed = 3.0          // slower than this the front wheel will not come up

    public init() {}
}
