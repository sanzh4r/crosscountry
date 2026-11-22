extension Track {
    /// Prototype layout: 150 cells, ending before the finish zone at cell 145. Mud and boost pads sit
    /// on the flat stretches between the terrain pieces, each in one lane.
    /// A starting point for tuning, not a final design.
    public static let prototype = Track(lengthCells: 150, pieces: [
        .init(kind: .smallHill, cell: 8), .init(kind: .bigHill, cell: 13), .init(kind: .bumps, cell: 20),
        .init(kind: .rockRamp, cell: 26), .init(kind: .smallHill, cell: 32), .init(kind: .smallHill, cell: 35),
        .init(kind: .bigHill, cell: 40), .init(kind: .bigHill, cell: 46), .init(kind: .rockRamp, cell: 54),
        .init(kind: .bumps, cell: 60), .init(kind: .bigHill, cell: 66), .init(kind: .smallHill, cell: 73),
        .init(kind: .rockRamp, cell: 78), .init(kind: .bigHill, cell: 85), .init(kind: .bumps, cell: 91),
        .init(kind: .smallHill, cell: 97), .init(kind: .smallHill, cell: 100), .init(kind: .bigHill, cell: 105),
        .init(kind: .rockRamp, cell: 112), .init(kind: .bigHill, cell: 118), .init(kind: .smallHill, cell: 125),
        .init(kind: .bigHill, cell: 130), .init(kind: .rockRamp, cell: 137),
        .init(kind: .boostPad, cell: 6, lane: 0), .init(kind: .mud, cell: 17, lane: 1),
        .init(kind: .boostPad, cell: 24, lane: 2), .init(kind: .mud, cell: 29, lane: 0),
        .init(kind: .mud, cell: 37, lane: 2), .init(kind: .boostPad, cell: 38, lane: 1),
        .init(kind: .mud, cell: 50, lane: 1), .init(kind: .boostPad, cell: 51, lane: 0),
        .init(kind: .mud, cell: 57, lane: 2), .init(kind: .boostPad, cell: 63, lane: 1),
        .init(kind: .mud, cell: 70, lane: 0), .init(kind: .mud, cell: 76, lane: 1),
        .init(kind: .boostPad, cell: 82, lane: 2), .init(kind: .mud, cell: 89, lane: 1),
        .init(kind: .boostPad, cell: 95, lane: 0), .init(kind: .mud, cell: 103, lane: 2),
        .init(kind: .mud, cell: 109, lane: 0), .init(kind: .boostPad, cell: 110, lane: 1),
        .init(kind: .mud, cell: 116, lane: 1), .init(kind: .boostPad, cell: 122, lane: 2),
        .init(kind: .mud, cell: 128, lane: 0), .init(kind: .boostPad, cell: 135, lane: 1),
    ])
}
