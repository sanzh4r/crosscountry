import Testing
import Foundation
@testable import RaceCore

struct AirTests {
    let flat = Track(lengthCells: 400, pieces: [])
    func airborne(y: Double = 0.5, vx: Double = 16, vy: Double = -2, angle: Double = 0, x: Double = 100) -> BikeState {
        var b = BikeState(); b.x = x; b.y = y; b.vx = vx; b.vy = vy; b.angle = angle; b.phase = .airborne; return b
    }
    func land(_ r: inout Race) { var n = 0; while r.bike.phase == .airborne && n < 600 { r.step(.init()); n += 1 } }

    @Test func takesOffFromBigHillAtSpeed() {
        var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .bigHill, cell: 10)])); var flew = false
        for _ in 0..<600 { r.step(.init(gas: true)); if r.bike.phase == .airborne { flew = true; #expect(r.bike.x > 44) } }   // only on the convex part, past the inflection
        #expect(flew)
    }
    @Test func leanRotatesOnlyInAir() {
        var r = Race(track: flat, bike: airborne(y: 50)); for _ in 0..<30 { r.step(.init(lean: 1)) }
        #expect(abs(r.bike.angle - (-1.25)) < 1e-9)
        for _ in 0..<30 { r.step(.init(lean: -5)) }; #expect(abs(r.bike.angle) < 1e-9)      // lean clamps to -1
        var g = Race(track: flat); for _ in 0..<30 { g.step(.init(gas: true, lean: 1)) }; #expect(g.bike.angle == 0)
    }
    @Test func cleanLandingKeepsSpeed() {
        var r = Race(track: flat, bike: airborne(angle: 0.1)); land(&r)
        #expect(r.bike.phase == .grounded); #expect(abs(r.bike.speed - 16) < 0.1); #expect(r.bike.y == 0)
    }
    @Test func sloppyLandingLosesSpeed() {
        var r = Race(track: flat, bike: airborne(angle: 0.5)); land(&r)
        #expect(r.bike.phase == .grounded); #expect(abs(r.bike.speed - 9.6) < 0.1)
    }
    @Test func badLandingCrashesThenResets() {
        var r = Race(track: flat, bike: airborne(angle: 1.2)); land(&r)
        #expect(r.bike.phase == .crashed(remaining: 2.0)); #expect(r.bike.speed == 0); let x = r.bike.x
        for _ in 0..<119 { r.step(.init(gas: true)) }; #expect(r.bike.x == x); #expect(r.bike.phase != .grounded)
        for _ in 0..<2 { r.step(.init()) }; #expect(r.bike.phase == .grounded); #expect(r.bike.angle == 0)
    }
    @Test func fullFlipEndingLevelIsClean() {
        var r = Race(track: flat, bike: airborne(angle: 2 * .pi + 0.1)); land(&r)
        #expect(r.bike.phase == .grounded); #expect(abs(r.bike.speed - 16) < 0.1)
        var u = Race(track: flat, bike: airborne(angle: .pi)); land(&u)          // upside down
        if case .crashed = u.bike.phase {} else { Issue.record("upside-down landing must crash") }
    }
    @Test func heatAndStallRunWhileAirborne() {
        var b = airborne(y: 200); b.stallRemaining = 1.0
        var r = Race(track: flat, bike: b); for _ in 0..<61 { r.step(.init()) }; #expect(r.bike.stallRemaining == 0)
    }
    @Test func finishesWhileAirborne() {
        var r = Race(track: Track(lengthCells: 20, pieces: []), bike: airborne(y: 5, x: 70))   // finishX = 72
        for _ in 0..<30 { r.step(.init()) }; #expect(r.bike.finished); let t = r.time
        for _ in 0..<60 { r.step(.init(gas: true)) }; #expect(r.time == t)
    }
    @Test func slowBikeFollowsRockRampLipWithoutCrashing() {      // ramp spans x 40…52, peak at 50.2
        var b = BikeState(); b.x = 49.5
        var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .rockRamp, cell: 10)]), bike: b)
        for _ in 0..<240 {
            r.step(.init(gas: true))
            if case .crashed = r.bike.phase { Issue.record("slow bike crashed at x = \(r.bike.x)") }
            #expect(r.bike.y >= r.terrain.height(at: r.bike.x) - 1e-9)
        }
        #expect(r.bike.x > 52)
    }
    @Test func fastBikeStillJumpsRockRamp() {
        var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .rockRamp, cell: 10)])); var flew = false
        for _ in 0..<600 { r.step(.init(gas: true)); if r.bike.phase == .airborne && r.bike.x > 50 { flew = true } }
        #expect(flew); #expect(r.bike.finished || r.bike.x > 60)
    }
}
