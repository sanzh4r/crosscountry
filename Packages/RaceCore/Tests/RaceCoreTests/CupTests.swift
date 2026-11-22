import Testing
import Foundation
@testable import RaceCore

struct CupTrackTests {
    static let tracks: [(String, Track)] = [("sunsetMile", .sunsetMile), ("rattleFlats", .rattleFlats),
                                            ("duskRun", .duskRun), ("mesaSteps", .mesaSteps), ("lastLight", .lastLight)]

    @Test func layoutTokensPlacePiecesInOrder() {
        let t = Track(layout: "p1 _ h H _ m0+m2 R")
        #expect(t.pieces == [.init(kind: .boostPad, cell: 6, lane: 1), .init(kind: .smallHill, cell: 8),
                             .init(kind: .bigHill, cell: 11), .init(kind: .mud, cell: 16, lane: 0),
                             .init(kind: .mud, cell: 16, lane: 2), .init(kind: .rockRamp, cell: 18)])
        #expect(t.lengthCells == 29)
    }
    @Test(arguments: 0..<5) func everyTrackIsValidAndRaceable(index: Int) throws {
        let (name, track) = CupTrackTests.tracks[index]
        try track.validate()
        var r = Race(track: track, rivals: 3)
        var riders = [Rival(skill: .rookie, seed: 3), Rival(skill: .steady, seed: 4), Rival(skill: .sharp, seed: 5)]
        var n = 0
        while !r.bikes.allSatisfy(\.finished) && n < 60 * 300 {
            var inputs = [RiderInput(gas: true)]
            for i in riders.indices { inputs.append(riders[i].input(for: i + 1, in: r)) }
            r.step(inputs); n += 1
        }
        let times = r.bikes.map { $0.finishTime ?? .infinity }
        print("cup track", name, track.lengthCells, "cells, gas only + rivals:", times.map { ($0 * 10).rounded() / 10 })
        let fastest = times.min() ?? 0, slowest = times.max() ?? .infinity
        #expect(fastest > 45); #expect(slowest < 130)
    }
}

struct CupTests {
    @Test func aNewCupStartsAtRaceOneWithNoPoints() {
        let c = Cup()
        #expect(c.current == 0); #expect(c.totals == [0, 0, 0, 0]); #expect(!c.canAdvance); #expect(!c.isFinished)
        #expect(c.round.id == "sunsetMile"); #expect(Cup.rounds.count == 5); #expect(c.placeInCurrentRace == nil)
    }
    @Test func pointsFollowFinishingPlaces() {
        var c = Cup(); c.record([2, 1, 4, 3])
        #expect(c.totals == [6, 10, 1, 3]); #expect(c.points(inRace: 0) == [6, 10, 1, 3]); #expect(c.canAdvance)
        #expect(c.placeInCurrentRace == 2)
    }
    @Test func fourthPlaceMustRetryAndARetryReplacesTheResult() {
        var c = Cup(); c.record([4, 1, 2, 3]); #expect(!c.canAdvance)
        c.advance(); #expect(c.current == 0)
        c.record([1, 2, 3, 4]); #expect(c.totals == [10, 6, 3, 1]); #expect(c.places.count == 1)
        c.advance(); #expect(c.current == 1); #expect(!c.canAdvance); #expect(c.round.id == "rattleFlats")
    }
    @Test func aBadResultIsIgnored() {
        var c = Cup(); c.record([1, 1, 2, 3]); c.record([1, 2, 3]); c.record([0, 1, 2, 3])
        #expect(c.places.isEmpty)
    }
    @Test func theCupEndsAfterFiveRaces() {
        var c = Cup()
        for _ in 0..<5 { c.record([3, 1, 2, 4]); c.advance() }
        #expect(c.isFinished); #expect(c.totals == [15, 50, 30, 5]); #expect(c.standings == [1, 2, 0, 3])
        #expect(c.round.id == "lastLight")
        c.record([1, 2, 3, 4]); c.advance(); #expect(c.totals == [15, 50, 30, 5]); #expect(c.current == 5)
    }
    @Test func equalPointsAreSplitByWinsThenRiderOrder() {
        var c = Cup()
        c.record([2, 1, 3, 4]); c.advance()      // 6, 10, 3, 1
        c.record([2, 4, 1, 3]); c.advance()      // 12, 11, 13, 4
        c.record([3, 2, 4, 1])                   // 15, 17, 14, 14
        #expect(c.totals == [15, 17, 14, 14]); #expect(c.standings == [1, 0, 2, 3])
        var d = Cup(); d.record([2, 1, 4, 3]); d.advance(); d.record([1, 2, 3, 4])   // 16, 16, 4, 4
        #expect(d.standings == [0, 1, 2, 3])
    }
    @Test func progressSurvivesSaving() throws {
        var c = Cup(); c.record([1, 2, 3, 4]); c.advance(); c.record([4, 3, 2, 1])
        let back = try JSONDecoder().decode(Cup.self, from: JSONEncoder().encode(c))
        #expect(back == c); #expect(back.current == 1); #expect(!back.canAdvance)
    }
    @Test func everyRoundHasThreeRivals() {
        for round in Cup.rounds { #expect(round.rivals.count == 3) }
        #expect(Set(Cup.rounds.map(\.id)).count == 5)
    }
}
