import Testing
@testable import RaceCore

struct SplitMix64: RandomNumberGenerator { var state: UInt64
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

func inputs(seed: UInt64, count: Int) -> [RiderInput] {       // each random input held for 20 steps
    var g = SplitMix64(state: seed)
    return (0..<count / 20).flatMap { _ -> [RiderInput] in
        let i = RiderInput(gas: Bool.random(using: &g), boost: Bool.random(using: &g), lean: Double.random(in: -1...1, using: &g))
        return Array(repeating: i, count: 20) }
}

struct SoakTests {
    @Test func prototypeTrackIsValid() throws { try Track.prototype.validate() }

    /// Every step is live: once the bike finishes, the next step starts a fresh race. Violations are collected
    /// per invariant (first violating step recorded) and asserted once at the end, so a broken invariant reports
    /// one clear failure instead of thousands. Hazard step counts prove the soak reaches what it guards.
    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64]) func soakKeepsInvariants(seed: UInt64) {
        var r = Race(track: .prototype); var lastX = r.bike.x
        var aboveGround: Int?, finite: Int?, heatInRange: Int?, forward: Int?
        var airborne = 0, stalled = 0, crashed = 0
        for (n, i) in inputs(seed: seed, count: 20_000).enumerated() {
            if r.bike.finished { r = Race(track: .prototype); lastX = r.bike.x }
            r.step(i); let b = r.bike
            if aboveGround == nil, !(b.y >= r.terrain.height(at: b.x) - 1e-6) { aboveGround = n }
            if finite == nil, ![b.x, b.y, b.vx, b.vy, b.angle, b.heat, b.stallRemaining].allSatisfy(\.isFinite) { finite = n }
            if heatInRange == nil, !(0...1).contains(b.heat) { heatInRange = n }
            if forward == nil, !(b.x >= lastX) { forward = n }; lastX = b.x
            if b.phase == .airborne { airborne += 1 }
            if b.stallRemaining > 0 { stalled += 1 }
            if case .crashed = b.phase { crashed += 1 }
        }
        #expect(aboveGround == nil, "bike below terrain, first at step \(aboveGround ?? -1)")
        #expect(finite == nil, "non-finite bike state, first at step \(finite ?? -1)")
        #expect(heatInRange == nil, "heat outside 0...1, first at step \(heatInRange ?? -1)")
        #expect(forward == nil, "bike moved backwards, first at step \(forward ?? -1)")
        #expect(airborne > 0, "seed \(seed) never airborne"); #expect(stalled > 0, "seed \(seed) never stalled")
        #expect(crashed > 0, "seed \(seed) never crashed")
    }
    @Test func prototypeTrackCanBeFinishedOnGasAlone() {
        var r = Race(track: .prototype); var n = 0
        while !r.bike.finished && n < 60 * 600 { r.step(.init(gas: true)); n += 1 }
        #expect(r.bike.finished)
    }
    @Test func sameInputsGiveSameRace() {
        let seq = inputs(seed: 42, count: 6_000); var a = Race(track: .prototype), b = Race(track: .prototype)
        var diverged: Int?
        for (n, i) in seq.enumerated() { a.step(i); b.step(i); if diverged == nil, a.bike != b.bike { diverged = n } }
        #expect(diverged == nil, "races diverged first at step \(diverged ?? -1)")
        #expect(a.bike == b.bike); #expect(a.time == b.time)
    }
}
