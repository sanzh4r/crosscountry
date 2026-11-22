extension Track {
    /// Builds a track from a compact layout, read left to right from the end of the start zone.
    /// Tokens, separated by spaces: `h` small hill, `H` big hill, `R` rock ramp, `b` bumps, `_` one
    /// flat cell, `m0`...`m2` mud and `p0`...`p2` a boost pad in that lane. Surface tokens joined by
    /// `+` share their first cell (`m0+m2` leaves only the middle lane dry). The one flat cell that
    /// two terrain pieces need between them is added automatically.
    public init(layout: String) {
        var cell = Track.startZoneCells + 1
        var pieces: [PlacedPiece] = []
        var afterTerrain = false
        for token in layout.split(separator: " ") {
            if token == "_" {
                cell += 1
                afterTerrain = false
                continue
            }
            let terrain: [Substring: PieceKind] = ["h": .smallHill, "H": .bigHill, "R": .rockRamp, "b": .bumps]
            if let kind = terrain[token] {
                if afterTerrain { cell += 1 }
                pieces.append(PlacedPiece(kind: kind, cell: cell))
                cell += kind.widthCells
                afterTerrain = true
                continue
            }
            var width = 0
            for part in token.split(separator: "+") {
                guard let lane = part.last?.wholeNumberValue, part.count == 2, part.first == "m" || part.first == "p" else {
                    preconditionFailure("unknown track token \(token)")
                }
                let kind = part.first == "m" ? PieceKind.mud : .boostPad
                pieces.append(PlacedPiece(kind: kind, cell: cell, lane: lane))
                width = max(width, kind.widthCells)
            }
            cell += width
            afterTerrain = false
        }
        self.init(lengthCells: cell + 3 + Track.finishZoneCells, pieces: pieces)
    }

    /// Race 1: rolling small hills and plenty of boost pads.
    public static let sunsetMile = Track(layout: """
        p1 _ h h _ p2 _ h _ m0 _ H _ p1 _ _ h h h _ m1 _ p0 _ b _ p2 _ H _ _ m2 _ h h _ p1 _ _ H _ m0 _ \
        p2 _ h _ b _ p0 _ m1 _ h h h _ p1 _ H H _ m2 _ p0 _ _ h _ R _ p1 _ m0 _ h h _ b _ p2 _ H _ m1 _ \
        p0 _ h h _ _ p1 _ H _ h _ m2 _ p1 _ b _ h h _ p0 _ H _ p2 _ h h _ m0 _ p1 _ H _ b _ p0 _ h h h _ \
        m1 _ p2 _ H
        """)

    /// Race 2: washboard and long straights where mud and pads decide the lane.
    public static let rattleFlats = Track(layout: """
        p0 _ b b _ m1 _ p2 _ h _ b _ m0+m2 _ p1 _ _ H _ b b b _ p0 _ m1 _ m2 _ p0 _ h h _ b _ R _ m0 _ \
        p1 _ _ b b _ H _ p2 _ m1 _ m0 _ p2 _ b _ h _ b _ p1 _ m0+m1 _ p2 _ H _ b b _ m2 _ p0 _ R _ _ b _ \
        h h _ p1 _ m1 _ p0 _ m0 _ p2 _ b b b _ H _ p1 _ m2 _ b _ h _ p0 _ m0+m2 _ p1 _ b b _ H _ m1 _ \
        p2 _ b _ R _ p0 _ b _ h h _ p1 _ H
        """)

    /// Race 4: rock ramps and big hills stacked like steps.
    public static let mesaSteps = Track(layout: """
        p1 _ h R _ m0 _ H _ p2 _ R R _ m1 _ p0 _ h R H _ m2 _ m0 _ p1 _ H H _ R _ p2 _ m1 _ b _ R H _ \
        p0 _ m0+m2 _ p1 _ R R R _ m1 _ p2 _ H _ h R H _ p0 _ m2 _ m1 _ p0 _ H R _ b _ p1 _ m0 _ R H R _ \
        p2 _ m1+m2 _ p0 _ H H H _ m0 _ p1 _ R _ h R H _ m2 _ p0 _ R R _ b _ p1 _ m0+m1 _ p2 _ H R H _ \
        m1 _ p0 _ h R _ H H _ p2 _ m0 _ R R R _ p1 _ H
        """)

    /// Race 5: everything at once, with mud across two lanes and pads that lead into it.
    public static let lastLight = Track(layout: """
        p1 _ H R _ m0+m1 _ p2 _ b _ R R _ m1+m2 _ p0 _ m0 m1 m2 m1 m0 p2 _ H H _ R _ b b _ p1 _ m0+m2 _ \
        p1 m1 _ R R R _ p0 _ m1+m2 _ H _ h h h _ m0+m1 _ p2 _ R H R _ m2 m1 m0 m1 p2 _ b _ H H H _ p0 _ \
        m1+m2 _ p0 _ m0 _ h R H _ p1 _ m1 m0 m1 m2 \
        p0 _ R R R _ b _ m0+m1 _ p2 _ H R H _ m1+m2 _ p0 _ b b _ R _ p1 m1 _ H H _ m0+m2 _ p1 _ R H R H _ \
        p1 _ H
        """)
}
