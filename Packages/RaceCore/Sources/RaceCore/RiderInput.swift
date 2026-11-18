public struct RiderInput: Equatable, Sendable {
    public var gas = false, boost = false
    public var lean = 0.0                     // -1 lean back (nose up) ... +1 lean forward (nose down); clamped on use

    public init(gas: Bool = false, boost: Bool = false, lean: Double = 0) {
        self.gas = gas
        self.boost = boost
        self.lean = lean
    }
}
