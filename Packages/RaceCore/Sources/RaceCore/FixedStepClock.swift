/// Turns variable frame times into whole simulation steps of `Race.dt`.
public struct FixedStepClock: Sendable {
    public static let maxStepsPerAdvance = 5

    /// Tolerance (in steps) so frame times that are a whole number of steps up to rounding still count in full.
    private static let stepEpsilon = 1e-9

    private var accumulated = 0.0

    public init() {}

    /// Whole steps of `Race.dt` owed after `seconds` more elapsed time. The fractional remainder carries over,
    /// except when more than `maxStepsPerAdvance` steps were owed: then all surplus is dropped.
    /// Negative, NaN and infinite input is ignored.
    public mutating func advance(by seconds: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        let total = accumulated + seconds
        let owed = (total / Race.dt + FixedStepClock.stepEpsilon).rounded(.down)
        if owed > Double(FixedStepClock.maxStepsPerAdvance) {
            accumulated = 0
            return FixedStepClock.maxStepsPerAdvance
        }
        accumulated = max(0, total - owed * Race.dt)
        return Int(owed)
    }
}
