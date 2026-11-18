import Testing
@testable import RaceCore

struct FixedStepClockTests {
    @Test func oneFrameOneStep() { var c = FixedStepClock(); #expect(c.advance(by: 1.0 / 60) == 1) }
    @Test func accumulatesPartialFrames() { var c = FixedStepClock(); #expect(c.advance(by: 0.008) == 0); #expect(c.advance(by: 0.010) == 1) }
    @Test func capsCatchUpAndDropsSurplus() { var c = FixedStepClock(); #expect(c.advance(by: 3.0) == 5); #expect(c.advance(by: 0) == 0) }
    @Test func ignoresBadInput() { var c = FixedStepClock(); for s in [-1.0, .nan, .infinity] { #expect(c.advance(by: s) == 0) } }
}
