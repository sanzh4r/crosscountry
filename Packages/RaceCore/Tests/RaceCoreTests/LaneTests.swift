import Testing
@testable import RaceCore

struct LaneTests {
    let flat = Track(lengthCells: 400, pieces: [])
    func run(_ r: inout Race, _ n: Int, _ inputs: [RiderInput]) { for _ in 0..<n { r.step(inputs) } }

    @Test func gridPutsFourBikesInThreeLanesWithoutOverlap() {
        let r = Race(track: flat, rivals: 3)
        let lanes = r.bikes.map { $0.targetLane }; #expect(lanes == [1, 0, 2, 0])
        #expect(r.bikes[3].x < r.bikes[1].x - r.tuning.bikeLength)
    }
    @Test func laneChangeTakesItsTimeAndStopsAtTheEdge() {
        var r = Race(track: flat)
        r.step(.init(laneChange: 1)); #expect(r.bike.targetLane == 2); #expect(r.bike.lane > 1 && r.bike.lane < 2)
        run(&r, 20, [.init()]); #expect(r.bike.lane == 2)
        r.step(.init(laneChange: 1)); #expect(r.bike.targetLane == 2)
    }
    @Test func heldLaneButtonMovesOneLaneAtATime() {
        var r = Race(track: flat); run(&r, 5, [.init(laneChange: -1)])
        #expect(r.bike.targetLane == 0); #expect(r.bike.lane > 0)
    }
    @Test func laneChangeIntoAnOccupiedSpotIsRefusedAndCostsSpeed() {
        var r = Race(track: flat, rivals: 1)                      // rival beside the player in lane 0
        run(&r, 120, [.init(gas: true), .init(gas: true)])
        let before = r.bike.speed
        r.step([.init(gas: true, laneChange: -1), .init(gas: true)])
        #expect(r.bike.targetLane == 1); #expect(r.bike.speed < before); #expect(r.bike.laneCooldown > 0)
    }
    @Test func rearBikeIsHeldToTheSpeedOfTheBikeAhead() {
        var r = Race(track: flat, rivals: 3)                      // bike 3 starts behind bike 1 in lane 0
        for _ in 0..<600 {
            r.step([.init(), .init(gas: true), .init(), .init(boost: true)])
            #expect(r.bikes[3].x < r.bikes[1].x)
        }
        #expect(r.bikes[1].x - r.bikes[3].x < r.tuning.bikeLength + 0.5)
    }
    @Test func mudSlowsOnlyItsLane() {
        let t = Track(lengthCells: 60, pieces: [.init(kind: .mud, cell: 20, lane: 1)])
        var r = Race(track: t, rivals: 1); var slowest = (99.0, 99.0)
        while r.bike.x < 90 {
            r.step([.init(gas: true), .init(gas: true)])
            if r.bike.x > 81 && r.bike.x < 88 { slowest.0 = min(slowest.0, r.bike.speed) }
            if r.bikes[1].x > 81 && r.bikes[1].x < 88 { slowest.1 = min(slowest.1, r.bikes[1].speed) }
        }
        #expect(abs(slowest.0 - r.tuning.mudTopSpeed) < 0.5); #expect(slowest.1 > r.tuning.normalTopSpeed - 0.5)
    }
    @Test func boostPadGivesSpeedWithoutHeat() {
        let t = Track(lengthCells: 60, pieces: [.init(kind: .boostPad, cell: 20, lane: 1)])
        var r = Race(track: t); var peak = 0.0
        while r.bike.x < 90 { r.step(.init(gas: true)); peak = max(peak, r.bike.speed) }
        #expect(peak == r.tuning.boostPadSpeed); #expect(r.bike.heat == 0)
    }
    @Test func positionsFollowDistanceThenFinishOrder() {
        var r = Race(track: Track(lengthCells: 30, pieces: []), rivals: 2)
        run(&r, 60, [.init(), .init(gas: true), .init(boost: true)])
        #expect(r.position(of: 2) == 1); #expect(r.position(of: 1) == 2); #expect(r.position(of: 0) == 3)
        run(&r, 900, [.init(gas: true), .init(gas: true), .init(boost: true)])
        let allFinished = r.bikes.allSatisfy { $0.finished }; #expect(allFinished)
        let places = Set((0..<3).map { r.position(of: $0) }); #expect(places == [1, 2, 3]); #expect(r.position(of: 0) == 3)
    }
}

struct RivalTests {
    func race(seed: UInt64) -> (Race, [Double]) {
        var r = Race(track: .prototype, rivals: 3)
        var riders = [Rival(skill: .rookie, seed: seed), Rival(skill: .steady, seed: seed + 1),
                      Rival(skill: .sharp, seed: seed + 2)]
        var n = 0
        while !r.bikes.dropFirst().allSatisfy(\.finished) && n < 60 * 240 {
            var inputs = [RiderInput()]
            for i in riders.indices { inputs.append(riders[i].input(for: i + 1, in: r)) }
            r.step(inputs); n += 1
        }
        return (r, r.bikes.dropFirst().map { $0.finishTime ?? .infinity })
    }

    @Test(arguments: [UInt64(1), 7, 99]) func everyRivalFinishesThePrototypeTrack(seed: UInt64) {
        let (_, times) = race(seed: seed)
        let slowest = times.max() ?? .infinity; #expect(slowest < 120)
    }
    @Test func sameSeedGivesTheSameRace() {
        #expect(race(seed: 5).1 == race(seed: 5).1)
    }
    @Test func sharperRivalsAreFasterOnAverage() {
        var totals = [0.0, 0.0, 0.0]
        for seed in UInt64(1)...12 { for (i, t) in race(seed: seed * 10).1.enumerated() { totals[i] += t } }
        print("rival average times", totals.map { $0 / 12 })
        #expect(totals[2] < totals[0])
    }
}
