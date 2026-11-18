import Testing
import Foundation
@testable import RaceCore

@Test func validTrackPasses() throws {
    try Track(lengthCells: 40, pieces: [
        .init(kind: .smallHill, cell: 6), .init(kind: .mud, cell: 9, lane: 1),
        .init(kind: .boostPad, cell: 9, lane: 2), .init(kind: .bigHill, cell: 13)]).validate()
}
@Test(arguments: [
    ([PlacedPiece(kind: .smallHill, cell: 6), .init(kind: .bigHill, cell: 8)], TrackError.noFlatGap(cell: 8)),
    ([.init(kind: .smallHill, cell: 6), .init(kind: .rockRamp, cell: 7)], .overlap(cell: 7)),
    ([.init(kind: .smallHill, cell: 6), .init(kind: .mud, cell: 6, lane: 0)], .overlap(cell: 6)),
    ([.init(kind: .mud, cell: 8, lane: 1), .init(kind: .boostPad, cell: 9, lane: 1)], .overlap(cell: 9)),
    ([.init(kind: .smallHill, cell: 3)], .outsideBuildZone(cell: 3)),
    ([.init(kind: .bigHill, cell: 33)], .outsideBuildZone(cell: 33)),   // 33..36 enters finish zone 35..39
    ([.init(kind: .smallHill, cell: -1)], .outsideBuildZone(cell: -1)),
    ([.init(kind: .mud, cell: 8)], .laneRequired(cell: 8)),
    ([.init(kind: .smallHill, cell: 8, lane: 0)], .laneNotAllowed(cell: 8)),
    ([.init(kind: .mud, cell: 8, lane: 3)], .badLane(cell: 8)),
])
func invalidTrackThrows(pieces: [PlacedPiece], expected: TrackError) {
    #expect(throws: expected) { try Track(lengthCells: 40, pieces: pieces).validate() }
}
@Test func tooShort() { #expect(throws: TrackError.trackTooShort) { try Track(lengthCells: 19, pieces: []).validate() } }
@Test func roundTripsThroughJSON() throws {
    let t = Track(lengthCells: 40, pieces: [.init(kind: .rockRamp, cell: 10), .init(kind: .mud, cell: 20, lane: 2)])
    #expect(try Track.load(from: JSONEncoder().encode(t)) == t)
}
@Test func unknownKindFailsToLoad() {
    let json = Data(#"{"lengthCells":40,"pieces":[{"kind":"loop","cell":8}]}"#.utf8)
    #expect(throws: DecodingError.self) { try Track.load(from: json) }
}
@Test func invalidJSONTrackFailsToLoad() {
    let json = Data(#"{"lengthCells":40,"pieces":[{"kind":"mud","cell":8}]}"#.utf8)
    #expect(throws: TrackError.laneRequired(cell: 8)) { try Track.load(from: json) }
}
@Test func hugeCellFailsToLoadWithoutCrashing() {
    let json = Data(#"{"lengthCells":40,"pieces":[{"kind":"smallHill","cell":9223372036854775807}]}"#.utf8)
    #expect(throws: TrackError.outsideBuildZone(cell: Int.max)) { try Track.load(from: json) }
}
@Test func hugeLengthDoesNotCrash() throws {
    try Track(lengthCells: Int.max, pieces: [.init(kind: .smallHill, cell: 6)]).validate()
    #expect(throws: TrackError.outsideBuildZone(cell: Int.max - 1)) {
        try Track(lengthCells: Int.max, pieces: [.init(kind: .smallHill, cell: Int.max - 1)]).validate()
    }
}
