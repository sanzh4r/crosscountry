import Testing
import Foundation
@testable import RaceCore

struct GroundRidingTests {
    let flat = Track(lengthCells: 60, pieces: [])
    func run(_ r: inout Race, _ n: Int, _ i: RiderInput) { for _ in 0..<n { r.step(i) } }

    @Test func gasReachesNormalTopSpeedAndHolds() {
        var r = Race(track: flat); var peak = 0.0
        for _ in 0..<300 { r.step(.init(gas: true)); peak = max(peak, r.bike.speed) }
        #expect(abs(r.bike.speed - 16) < 0.2); #expect(peak <= 16 + 8 * Race.dt)
    }
    @Test func coastsToStopWithoutGoingBackwards() {
        var r = Race(track: flat); run(&r, 120, .init(gas: true)); let x0 = r.bike.x
        run(&r, 600, .init()); #expect(r.bike.speed == 0); #expect(r.bike.x > x0)
        let x1 = r.bike.x; run(&r, 60, .init()); #expect(r.bike.x == x1)
    }
    @Test func followsTerrainWhenSlow() {
        var t = Tuning(); t.normalTopSpeed = 4
        var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .smallHill, cell: 6)]), tuning: t)
        for _ in 0..<900 { r.step(.init(gas: true)); #expect(r.bike.phase == .grounded)
            #expect(abs(r.bike.y - r.terrain.height(at: r.bike.x)) < 1e-9) }
        #expect(r.bike.x > 32)
    }
    @Test func stoppedOnUphillDoesNotRollBack() {
        var b = BikeState(); b.x = 26
        var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .smallHill, cell: 6)]), bike: b)
        run(&r, 120, .init()); #expect(r.bike.x == 26)
    }
    @Test func pullsAwayFromStandstillOnSteepestSlope() {      // big hill at cell 10 is steepest at x = 44
        var b = BikeState(); b.x = 44
        var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .bigHill, cell: 10)]), bike: b)
        #expect(abs(r.bike.y - 1.75) < 1e-9); run(&r, 60, .init(gas: true)); #expect(r.bike.x > 45)
    }
    @Test func finishFreezesTimeAndIgnoresInput() {
        var r = Race(track: Track(lengthCells: 20, pieces: [])); var steps = 0
        while !r.bike.finished && steps < 5000 { r.step(.init(gas: true)); steps += 1 }
        #expect(r.bike.finished); let t = r.time
        run(&r, 600, .init(gas: true, boost: true)); #expect(r.time == t); #expect(r.bike.speed == 0)
    }
    @Test func timeAdvancesByDtPerStep() { var r = Race(track: flat); run(&r, 60, .init()); #expect(abs(r.time - 1) < 1e-9) }
}
