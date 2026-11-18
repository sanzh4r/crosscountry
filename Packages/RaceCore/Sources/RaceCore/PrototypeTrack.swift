extension Track {
    /// Grey-box prototype layout: 150 cells, terrain pieces only, ending before the finish zone at cell 145.
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
    ])
}
