import Testing
import Foundation
@testable import RaceCore

struct BuilderTests {
    let empty = Track(lengthCells: 80, pieces: [])

    @Test func aPieceGoesWhereTheRulesAllow() {
        let t = empty.adding(.init(kind: .bigHill, cell: 10))
        #expect(t?.pieces == [.init(kind: .bigHill, cell: 10)])
        #expect(t?.adding(.init(kind: .smallHill, cell: 14)) == nil)          // no flat cell between
        #expect(t?.adding(.init(kind: .smallHill, cell: 15)) != nil)
        #expect(t?.adding(.init(kind: .mud, cell: 12, lane: 1)) == nil)       // on the hill
        #expect(t?.adding(.init(kind: .mud, cell: 14, lane: 1)) != nil)
    }
    @Test func startAndFinishStretchesStayEmpty() {
        #expect(empty.adding(.init(kind: .smallHill, cell: 4)) == nil)
        #expect(empty.adding(.init(kind: .smallHill, cell: 5)) != nil)
        #expect(empty.adding(.init(kind: .smallHill, cell: 73)) != nil)
        #expect(empty.adding(.init(kind: .smallHill, cell: 74)) == nil)
        #expect(empty.adding(.init(kind: .boostPad, cell: -3, lane: 0)) == nil)
    }
    @Test func surfacesNeedALaneAndMayShareACellAcrossLanes() {
        #expect(empty.adding(.init(kind: .mud, cell: 20)) == nil)
        #expect(empty.adding(.init(kind: .bumps, cell: 20, lane: 1)) == nil)
        let t = empty.adding(.init(kind: .mud, cell: 20, lane: 0))
        #expect(t?.adding(.init(kind: .boostPad, cell: 21, lane: 0)) == nil)
        #expect(t?.adding(.init(kind: .boostPad, cell: 21, lane: 2)) != nil)
    }
    @Test func findsThePieceUnderACell() {
        let t = Track(lengthCells: 80, pieces: [.init(kind: .bigHill, cell: 10), .init(kind: .mud, cell: 20, lane: 0),
                                                .init(kind: .boostPad, cell: 21, lane: 2)])
        #expect(t.pieceIndex(atCell: 13, lane: 2) == 0); #expect(t.pieceIndex(atCell: 14, lane: 2) == nil)
        #expect(t.pieceIndex(atCell: 21, lane: 0) == 1); #expect(t.pieceIndex(atCell: 21, lane: 2) == 2)
        #expect(t.pieceIndex(atCell: 21, lane: 1) == 1); #expect(t.pieceIndex(atCell: 22, lane: 0) == nil)
    }
    @Test func anyBuiltTrackCanBeFinishedByEveryRider() throws {
        // The densest layout the rules allow: big hills and rock ramps one flat cell apart, mud between.
        var t = Track(lengthCells: 80, pieces: []); var cell = 5; var ramp = false
        while let next = t.adding(.init(kind: ramp ? .rockRamp : .bigHill, cell: cell)) {
            t = next; cell = t.pieces.last!.endCell
            if let muddy = t.adding(.init(kind: .mud, cell: cell, lane: 1)) { t = muddy; cell += 2 } else { cell += 1 }
            ramp.toggle()
        }
        try t.validate(); #expect(t.pieces.count > 15)
        var r = Race(track: t, rivals: 3)
        var riders = [Rival(skill: .rookie, seed: 1), Rival(skill: .steady, seed: 2), Rival(skill: .sharp, seed: 3)]
        var n = 0
        while !r.bikes.allSatisfy(\.finished) && n < 60 * 240 {
            var inputs = [RiderInput(gas: true)]
            for i in riders.indices { inputs.append(riders[i].input(for: i + 1, in: r)) }
            r.step(inputs); n += 1
        }
        let all = r.bikes.allSatisfy(\.finished); #expect(all)
    }
}

struct TrackLibraryTests {
    @Test func newTracksGetTheirOwnNamesAndLengths() {
        var lib = TrackLibrary()
        let a = lib.create(.short), b = lib.create(.long)
        #expect(a?.name == "TRACK 1"); #expect(b?.name == "TRACK 2"); #expect(a?.track.lengthCells == 80)
        #expect(b?.track.lengthCells == 260); #expect(lib.tracks.count == 2)
        lib.delete(id: 1); let c = lib.create(.medium)
        #expect(c?.name == "TRACK 3"); #expect(lib.tracks.map(\.id) == [2, 3])
    }
    @Test func theLibraryHoldsSixTracks() {
        var lib = TrackLibrary()
        for _ in 0..<6 { let made = lib.create(.short); #expect(made != nil) }
        #expect(lib.isFull); let extra = lib.create(.short); #expect(extra == nil)
    }
    @Test func savingKeepsAValidLayoutAndRefusesABrokenOne() {
        var lib = TrackLibrary(); let id = lib.create(.short)!.id
        let good = Track(lengthCells: 80, pieces: [.init(kind: .bumps, cell: 30)])
        let saved = lib.save(good, id: id); #expect(saved); #expect(lib.tracks[0].track == good)
        let broken = lib.save(Track(lengthCells: 80, pieces: [.init(kind: .bumps, cell: 2)]), id: id)
        let unknown = lib.save(good, id: 99)
        #expect(!broken); #expect(!unknown); #expect(lib.tracks[0].track == good)
    }
    @Test func theLibrarySurvivesSaving() throws {
        var lib = TrackLibrary(); let id = lib.create(.medium)!.id
        lib.save(Track(lengthCells: 160, pieces: [.init(kind: .mud, cell: 9, lane: 2)]), id: id)
        let back = try JSONDecoder().decode(TrackLibrary.self, from: JSONEncoder().encode(lib))
        #expect(back == lib); var again = back; let next = again.create(.short); #expect(next?.name == "TRACK 2")
    }
    @Test func everyLengthIsAValidEmptyTrack() throws {
        for length in TrackLibrary.Length.allCases { try Track(lengthCells: length.rawValue, pieces: []).validate() }
    }
}
