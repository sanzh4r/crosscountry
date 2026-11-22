extension Track {
    /// The first full-length race: 322 cells (1288 m), about 70 seconds for a clean ride. It is built in
    /// sections that each ask for one thing: hills to learn on, a straight where heat is the limit,
    /// tall jumps, washboard, and lane puzzles where a pad leads into mud.
    public static let duskRun = Track(lengthCells: 322, pieces: [
        // Warm-up, from cell 5.
        .init(kind: .boostPad, cell: 6, lane: 1), .init(kind: .smallHill, cell: 8),
        .init(kind: .smallHill, cell: 13), .init(kind: .bumps, cell: 17), .init(kind: .mud, cell: 21, lane: 0),
        .init(kind: .bigHill, cell: 24), .init(kind: .boostPad, cell: 29, lane: 2),
        // Rhythm, from cell 31.
        .init(kind: .smallHill, cell: 31), .init(kind: .smallHill, cell: 34),
        .init(kind: .smallHill, cell: 37), .init(kind: .mud, cell: 39, lane: 1),
        .init(kind: .boostPad, cell: 42, lane: 0), .init(kind: .rockRamp, cell: 43),
        .init(kind: .mud, cell: 47, lane: 2), .init(kind: .rockRamp, cell: 49),
        .init(kind: .bigHill, cell: 54), .init(kind: .boostPad, cell: 59, lane: 1),
        .init(kind: .mud, cell: 61, lane: 0),
        // First straight, from cell 63.
        .init(kind: .mud, cell: 63, lane: 1), .init(kind: .boostPad, cell: 64, lane: 2),
        .init(kind: .mud, cell: 67, lane: 0), .init(kind: .mud, cell: 67, lane: 2),
        .init(kind: .boostPad, cell: 70, lane: 1), .init(kind: .mud, cell: 71, lane: 1),
        .init(kind: .bumps, cell: 73), .init(kind: .boostPad, cell: 77, lane: 0),
        // Big air, from cell 79.
        .init(kind: .bigHill, cell: 79), .init(kind: .bigHill, cell: 85), .init(kind: .bigHill, cell: 91),
        .init(kind: .mud, cell: 96, lane: 1), .init(kind: .boostPad, cell: 98, lane: 2),
        .init(kind: .rockRamp, cell: 99), .init(kind: .smallHill, cell: 103),
        .init(kind: .mud, cell: 105, lane: 0), .init(kind: .mud, cell: 107, lane: 2),
        // Washboard, from cell 109.
        .init(kind: .bumps, cell: 109), .init(kind: .bumps, cell: 113),
        .init(kind: .boostPad, cell: 116, lane: 1), .init(kind: .smallHill, cell: 118),
        .init(kind: .smallHill, cell: 121), .init(kind: .smallHill, cell: 124),
        .init(kind: .smallHill, cell: 127), .init(kind: .mud, cell: 130, lane: 1),
        .init(kind: .boostPad, cell: 131, lane: 0), .init(kind: .mud, cell: 132, lane: 2),
        // Mixed, from cell 134.
        .init(kind: .rockRamp, cell: 134), .init(kind: .boostPad, cell: 138, lane: 2),
        .init(kind: .bigHill, cell: 140), .init(kind: .rockRamp, cell: 146),
        .init(kind: .mud, cell: 150, lane: 0), .init(kind: .mud, cell: 150, lane: 1),
        .init(kind: .boostPad, cell: 152, lane: 2), .init(kind: .bigHill, cell: 153),
        .init(kind: .bumps, cell: 160), .init(kind: .boostPad, cell: 164, lane: 1),
        .init(kind: .mud, cell: 165, lane: 2), .init(kind: .mud, cell: 167, lane: 0),
        // Second straight, from cell 169.
        .init(kind: .boostPad, cell: 169, lane: 0), .init(kind: .mud, cell: 171, lane: 1),
        .init(kind: .mud, cell: 171, lane: 2), .init(kind: .boostPad, cell: 174, lane: 1),
        .init(kind: .mud, cell: 175, lane: 0), .init(kind: .smallHill, cell: 177),
        .init(kind: .smallHill, cell: 181), .init(kind: .boostPad, cell: 184, lane: 2),
        // Stairs, from cell 186.
        .init(kind: .smallHill, cell: 186), .init(kind: .rockRamp, cell: 189),
        .init(kind: .bigHill, cell: 193), .init(kind: .mud, cell: 197, lane: 0),
        .init(kind: .mud, cell: 197, lane: 2), .init(kind: .boostPad, cell: 200, lane: 1),
        .init(kind: .bigHill, cell: 201), .init(kind: .rockRamp, cell: 206),
        .init(kind: .smallHill, cell: 210), .init(kind: .boostPad, cell: 213, lane: 0),
        .init(kind: .mud, cell: 214, lane: 1), .init(kind: .mud, cell: 215, lane: 2),
        // Slalom, from cell 217.
        .init(kind: .mud, cell: 217, lane: 0), .init(kind: .mud, cell: 219, lane: 1),
        .init(kind: .mud, cell: 221, lane: 2), .init(kind: .mud, cell: 223, lane: 1),
        .init(kind: .mud, cell: 225, lane: 0), .init(kind: .boostPad, cell: 226, lane: 2),
        .init(kind: .mud, cell: 227, lane: 1), .init(kind: .bumps, cell: 229),
        // Triple rock, from cell 234.
        .init(kind: .rockRamp, cell: 234), .init(kind: .rockRamp, cell: 238),
        .init(kind: .rockRamp, cell: 242), .init(kind: .mud, cell: 245, lane: 1),
        .init(kind: .boostPad, cell: 247, lane: 0), .init(kind: .boostPad, cell: 248, lane: 2),
        .init(kind: .bigHill, cell: 249), .init(kind: .bigHill, cell: 255), .init(kind: .bumps, cell: 261),
        .init(kind: .bumps, cell: 265), .init(kind: .mud, cell: 269, lane: 0),
        .init(kind: .boostPad, cell: 270, lane: 1), .init(kind: .mud, cell: 271, lane: 2),
        // Finale, from cell 273.
        .init(kind: .bigHill, cell: 273), .init(kind: .bigHill, cell: 279),
        .init(kind: .boostPad, cell: 284, lane: 1), .init(kind: .rockRamp, cell: 286),
        .init(kind: .rockRamp, cell: 291), .init(kind: .mud, cell: 294, lane: 1),
        .init(kind: .bigHill, cell: 296), .init(kind: .smallHill, cell: 301),
        .init(kind: .smallHill, cell: 304), .init(kind: .boostPad, cell: 307, lane: 0),
        .init(kind: .boostPad, cell: 307, lane: 2), .init(kind: .mud, cell: 308, lane: 1),
        .init(kind: .bigHill, cell: 310),
    ])
}
