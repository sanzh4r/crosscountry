import Foundation

/// A computer rider. It only reads the race and answers with the same `RiderInput` a player gives,
/// so it has no speed the player lacks. Skill changes boost discipline, landing accuracy and lane
/// choice. The same seed gives the same ride.
public struct Rival: Sendable {
    public enum Skill: Int, Sendable, CaseIterable { case rookie, steady, sharp }

    public let skill: Skill
    private var random: SplitMix64
    /// False while the engine is being left to cool.
    private var boosting = true
    /// This jump's aiming mistake (radians), drawn at take-off.
    private var landingError = 0.0
    private var wasAirborne = false
    /// Whether this rider has noticed the obstacle or pad ahead; redrawn every few metres.
    private var alert = true
    private var alertCell = -1
    /// Whether the rider is rolling off the throttle on this stretch.
    private var coasting = false
    private var paceCell = -1

    public init(skill: Skill, seed: UInt64) {
        self.skill = skill
        random = SplitMix64(seed: seed)
    }

    /// Heat at which the rider stops boosting, and to which the engine must cool before boosting again.
    private var heatLimit: (stop: Double, resume: Double) {
        switch skill {
        case .rookie: (0.12, 0.02)
        case .steady: (0.45, 0.1)
        case .sharp: (0.3, 0.08)
        }
    }

    /// Largest aiming mistake on a landing (radians); clean is within 0.26 by default.
    private var maxLandingError: Double {
        switch skill {
        case .rookie: 0.6
        case .steady: 0.35
        case .sharp: 0.31
        }
    }

    /// Chance of noticing what lies ahead in time.
    private var attention: Double {
        switch skill {
        case .rookie: 0.4
        case .steady: 0.35
        case .sharp: 0.5
        }
    }

    /// Chance, drawn every few metres, of rolling off the throttle for that stretch. This is what
    /// keeps a rival at a human pace: a rider who never lifts is out of a player's reach.
    private var hesitation: Double {
        switch skill {
        case .rookie: 0.85
        case .steady: 0.8
        case .sharp: 0.7
        }
    }

    /// Speed the rider is happy to hold, as a share of the boosted top speed; above it they roll off.
    private var comfort: Double {
        switch skill {
        case .rookie: 0.3
        case .steady: 0.32
        case .sharp: 0.34
        }
    }

    public mutating func input(for index: Int, in race: Race) -> RiderInput {
        let bike = race.bikes[index]
        let cell = Int(bike.x / Track.cellWidth)
        if cell != paceCell {
            paceCell = cell
            if cell % 3 == 0 { coasting = random.unit(0...1) < hesitation }
        }
        // Never roll off when already slow, or the bike would stop on a climb.
        if bike.speed < race.tuning.normalTopSpeed * 0.5 { coasting = false }
        let tooFast = bike.speed > race.tuning.boostTopSpeed * comfort
        var input = RiderInput(gas: !coasting && !tooFast)

        // Boost on the ground only (it does nothing in the air), with a rest once the engine is hot.
        if bike.heat >= heatLimit.stop { boosting = false } else if bike.heat <= heatLimit.resume { boosting = true }
        input.boost = boosting && !coasting && !tooFast && bike.phase == .grounded

        // In the air, turn the bike toward the slope where it will come down, plus this jump's mistake.
        let airborne = bike.phase == .airborne
        if airborne && !wasAirborne { landingError = random.unit(-1...1) * maxLandingError }
        wasAirborne = airborne
        if airborne {
            let ahead = Rival.landingPoint(of: bike, in: race)
            let wanted = race.terrain.slope(at: ahead) + landingError
            input.lean = min(max((bike.angle - wanted) * 6, -1), 1)
        }

        input.laneChange = laneChoice(for: index, bike: bike, in: race)
        return input
    }

    /// Where the bike's current arc meets the ground.
    private static func landingPoint(of bike: BikeState, in race: Race) -> Double {
        var x = bike.x, y = bike.y, vy = bike.vy
        let dt = 1.0 / 30
        for _ in 0..<120 {
            x += bike.vx * dt
            y += vy * dt
            vy -= race.tuning.gravity * dt
            if y <= race.terrain.height(at: x) { break }
        }
        return x
    }

    /// Leaves a lane with mud or a slower bike ahead, and moves onto a boost pad when one is near.
    private mutating func laneChoice(for index: Int, bike: BikeState, in race: Race) -> Int {
        guard bike.phase == .grounded, bike.lane == Double(bike.targetLane), bike.laneCooldown == 0 else { return 0 }
        let cell = Int(bike.x / Track.cellWidth)
        if cell != alertCell {
            alertCell = cell
            if cell % 3 == 0 { alert = random.unit(0...1) < attention }
        }
        guard alert else { return 0 }
        let lane = bike.targetLane
        let look = max(bike.speed * 0.8, 6)

        func trouble(_ l: Int) -> Bool {
            if Rival.surface(.mud, in: race, lane: l, from: bike.x, to: bike.x + look) { return true }
            return race.bikes.enumerated().contains { j, other in
                j != index && other.targetLane == l && other.x > bike.x && other.x - bike.x < look * 0.6
                    && other.speed < bike.speed - 0.5
            }
        }
        func free(_ l: Int) -> Bool {
            (0..<Track.laneCount).contains(l) && !race.bikes.enumerated().contains { j, other in
                j != index && other.targetLane == l && abs(other.x - bike.x) < race.tuning.bikeLength * 1.5
            }
        }
        let sides = [lane - 1, lane + 1].filter(free)
        if trouble(lane) {
            if let clear = sides.first(where: { !trouble($0) }) { return clear - lane }
            return 0
        }
        if !Rival.surface(.boostPad, in: race, lane: lane, from: bike.x, to: bike.x + look),
           let pad = sides.first(where: { Rival.surface(.boostPad, in: race, lane: $0, from: bike.x, to: bike.x + look)
               && !trouble($0) }) {
            return pad - lane
        }
        return 0
    }

    private static func surface(_ kind: PieceKind, in race: Race, lane: Int, from: Double, to: Double) -> Bool {
        var x = from
        while x <= to {
            if race.surface(at: x, lane: lane) == kind { return true }
            x += Track.cellWidth / 2
        }
        return false
    }
}

/// Small seeded generator, so rivals repeat exactly.
struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit(_ range: ClosedRange<Double>) -> Double {
        let u = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * u
    }
}
