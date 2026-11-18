import Testing
@testable import RaceCore

struct FixedStepClockTests {
    @Test func oneFrameOneStep() { var c = FixedStepClock(); #expect(c.advance(by: 1.0 / 60) == 1) }
    @Test func accumulatesPartialFrames() { var c = FixedStepClock(); #expect(c.advance(by: 0.008) == 0); #expect(c.advance(by: 0.010) == 1) }
    @Test func capsCatchUpAndDropsSurplus() {
        var c = FixedStepClock(); #expect(c.advance(by: 3.0) == 5); #expect(c.advance(by: 0) == 0)
        #expect(c.advance(by: 0.01) == 0)                     // a kept remainder would make this 1
    }
    @Test func ignoresBadInput() { var c = FixedStepClock(); for s in [-1.0, .nan, .infinity] { #expect(c.advance(by: s) == 0) } }
    @Test func badInputLeavesAccumulatorUnchanged() {
        var c = FixedStepClock(); #expect(c.advance(by: 0.010) == 0); #expect(c.advance(by: .nan) == 0)
        #expect(c.advance(by: 0.010) == 1)
    }
}
