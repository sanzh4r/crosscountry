/// A tournament: the built-in tracks ridden in order against the same three rivals, with points for
/// each finishing place. Only the progress is stored; the rounds themselves are fixed.
public struct Cup: Codable, Equatable, Sendable {
    public struct Round: Sendable {
        /// Stable name for saved data, such as best times.
        public let id: String
        public let name: String
        public let track: Track
        /// Skill of each rival in this race, in rider order.
        public let rivals: [Rival.Skill]
        /// Seconds to beat on a solo run.
        public let targetTime: Double
    }

    /// Points for 1st, 2nd, 3rd and 4th.
    public static let points = [10, 6, 3, 1]
    /// Finishing at or above this place opens the next race.
    public static let worstPlaceToGoOn = 3
    /// The five races, easiest first. The strong rival changes from race to race so the table stays open.
    public static let rounds: [Round] = [
        Round(id: "sunsetMile", name: "SUNSET MILE", track: .sunsetMile, rivals: [.rookie, .steady, .rookie],
              targetTime: 52),
        Round(id: "rattleFlats", name: "RATTLE FLATS", track: .rattleFlats, rivals: [.steady, .rookie, .steady],
              targetTime: 57),
        Round(id: "duskRun", name: "DUSK RUN", track: .duskRun, rivals: [.rookie, .steady, .sharp], targetTime: 75),
        Round(id: "mesaSteps", name: "MESA STEPS", track: .mesaSteps, rivals: [.sharp, .steady, .steady],
              targetTime: 71),
        Round(id: "lastLight", name: "LAST LIGHT", track: .lastLight, rivals: [.steady, .sharp, .sharp], targetTime: 80),
    ]

    /// Index of the race being ridden; `rounds.count` once the cup is over.
    public private(set) var current = 0
    /// For each race ridden so far, every rider's finishing place (1 = winner), the player first.
    /// A retried race keeps only its latest result.
    public private(set) var places: [[Int]] = []

    public init() {}

    public var isFinished: Bool { current >= Cup.rounds.count }
    /// The race being ridden; the last one when the cup is over.
    public var round: Round { Cup.rounds[min(current, Cup.rounds.count - 1)] }
    /// The player's place in the current race, once it has been ridden.
    public var placeInCurrentRace: Int? { places.count > current ? places[current][0] : nil }
    /// True once the current race has a result good enough to go on.
    public var canAdvance: Bool { (placeInCurrentRace ?? .max) <= Cup.worstPlaceToGoOn }

    /// Stores the result of the current race, replacing an earlier attempt. `result` holds each
    /// rider's place, the player first. Ignored when the cup is over or the places are not 1...n once each.
    public mutating func record(_ result: [Int]) {
        guard !isFinished, result.sorted() == Array(1...Cup.points.count) else { return }
        if places.count > current { places[current] = result } else { places.append(result) }
    }

    /// Moves on to the next race, or ends the cup after the last one.
    public mutating func advance() {
        guard canAdvance else { return }
        current += 1
    }

    /// Points each rider took in race `index`.
    public func points(inRace index: Int) -> [Int] {
        guard places.indices.contains(index) else { return Array(repeating: 0, count: Cup.points.count) }
        return places[index].map { Cup.points[$0 - 1] }
    }

    /// Each rider's points so far, the player first.
    public var totals: [Int] {
        places.indices.reduce(into: Array(repeating: 0, count: Cup.points.count)) { sum, race in
            for (rider, earned) in points(inRace: race).enumerated() { sum[rider] += earned }
        }
    }

    /// Rider indices from the leader down. Equal points are split by more wins, then more second
    /// places, and so on; riders still level keep their rider order, the player first.
    public var standings: [Int] {
        let totals = totals
        func finishes(_ rider: Int) -> [Int] {
            (1...Cup.points.count).map { place in places.filter { $0[rider] == place }.count }
        }
        return totals.indices.sorted { a, b in
            if totals[a] != totals[b] { return totals[a] > totals[b] }
            let fa = finishes(a), fb = finishes(b)
            if fa != fb { return fa.lexicographicallyPrecedes(fb, by: >) }
            return a < b
        }
    }
}
