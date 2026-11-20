import Testing
@testable import RaceCore

struct HeatTests {
    let flat = Track(lengthCells: 400, pieces: [])

    @Test func boostReachesBoostTopSpeed() {
        var r = Race(track: flat); for _ in 0..<200 { r.step(.init(boost: true)) }
        #expect(abs(r.bike.speed - Tuning().boostTopSpeed) < 0.3)
    }
    @Test func overheatsAfterFillTimeThenStalls() {
        var r = Race(track: flat); var n = 0
        while r.bike.stallRemaining == 0 && n < 1000 { r.step(.init(boost: true)); n += 1 }
        #expect(abs(n - 240) <= 1); #expect(r.bike.heat == 0); #expect(abs(r.bike.stallRemaining - 3) < 0.02)
    }
    @Test func stalledEngineIgnoresGasThenRecovers() {
        var r = Race(track: flat); for _ in 0..<241 { r.step(.init(boost: true)) }
        var last = r.bike.speed
        for _ in 0..<170 { r.step(.init(gas: true, boost: true)); #expect(r.bike.speed < last || r.bike.speed == 0); last = r.bike.speed; #expect(r.bike.heat == 0) }
        for _ in 0..<300 { r.step(.init(gas: true)) }
        #expect(r.bike.stallRemaining == 0); #expect(abs(r.bike.speed - Tuning().normalTopSpeed) < 0.2)
    }
    @Test func heatDrainsWhenNotBoosting() {
        var r = Race(track: flat); for _ in 0..<120 { r.step(.init(boost: true)) }
        #expect(abs(r.bike.heat - 0.5) < 0.01)
        for _ in 0..<180 { r.step(.init(gas: true)) }; #expect(r.bike.heat < 0.01)
        for _ in 0..<60 { r.step(.init(gas: true)) }; #expect(r.bike.heat == 0)
    }
    @Test func speedSettlesBackToNormalAfterBoost() {
        var r = Race(track: flat); for _ in 0..<120 { r.step(.init(boost: true)) }
        for _ in 0..<300 { r.step(.init(gas: true)) }; #expect(abs(r.bike.speed - Tuning().normalTopSpeed) < 0.2)
    }
}
