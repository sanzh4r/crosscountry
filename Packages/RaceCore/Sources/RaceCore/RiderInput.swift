public struct RiderInput: Equatable, Sendable {
    public var gas = false, boost = false
    public var lean = 0.0                     // -1 lean back (nose up) ... +1 lean forward (nose down); clamped on use

    /// -1 one lane toward the far side, +1 toward the near side, 0 stay.
    public var laneChange = 0

    public init(gas: Bool = false, boost: Bool = false, lean: Double = 0, laneChange: Int = 0) {
        self.laneChange = laneChange
        self.gas = gas
        self.boost = boost
        self.lean = lean
    }
}
