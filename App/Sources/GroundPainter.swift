import Foundation

/// Colours the cut face of the ground pixel by pixel: dithered sand bands, or level sandstone strata
/// under rock ramps. A port of `ground_colour` / `rock_colour` in art/compose.py; results are tone
/// indices (0 = lightest) into the five sand or rock tones of art.json.
enum GroundPainter {
    private static let bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    private static let sandEdges = [5.0, 26, 70, 150]
    /// (thickness in pixels, tone), repeating upward. Uneven so it never reads as brickwork.
    private static let strata = [(11, 3), (5, 2), (14, 3), (4, 4), (9, 2), (7, 3), (16, 2), (5, 4), (12, 3), (8, 2)]
    private static let strataTotal = strata.reduce(0) { $0 + $1.0 }

    private static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
    private static func floorDiv(_ a: Int, _ n: Int) -> Int { (a - mod(a, n)) / n }

    private static func hash(_ a: Int, _ b: Int = 0) -> Int {
        var h = (a &* 73_856_093) ^ (b &* 19_349_663) ^ 0x9E37_79B9
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return (h ^ (h >> 16)) & 0xFFFF
    }

    /// Tone of sand `depth` pixels under the surface in world pixel column `x`.
    static func sand(x: Int, depth: Int) -> Int {
        if depth < 2 { return 0 }
        if depth < 5 { return 1 }
        var band = 1
        let dither = Double(bayer[depth % 4][mod(x, 4)] - 8)
        for (i, edge) in sandEdges.enumerated() where Double(depth) + dither * (0.5 + Double(i) * 0.6) > edge {
            band = min(i + 1, 4)
        }
        let h = ((x &* 73_856_093) ^ (depth &* 19_349_663)) & 0xFFFF
        if depth > 6 {
            if h < 380 { band = min(band + 1, 4) }          // dark pebble
            else if h < 560 { band = max(band - 1, 1) }     // light grain
        }
        return band
    }

    /// Tone of sandstone: a lit skin following the surface, strata level by altitude `alt` (pixels
    /// above height 0).
    static func rock(x: Int, depth: Int, alt: Int) -> Int {
        if depth < 2 { return 0 }
        if depth < 4 { return 1 }
        let wobble = mod(floorDiv(x, 12), 2) == 1 ? hash(floorDiv(x, 24)) % 3 - 1 : 0
        let level = alt + wobble + 4096
        var a = mod(level, strataTotal)
        for (i, (thick, tone)) in strata.enumerated() {
            if a < thick {
                if a == thick - 1 { return 4 }                              // dark seam on top
                if a == thick - 2 && thick > 5 { return max(tone - 1, 1) }  // lit lip under it
                let layer = level / strataTotal * strata.count + i
                let gap = 71 + hash(layer) % 97
                if thick > 6, mod(x + hash(layer, 7) % gap, gap) == 0, hash(x, layer) % 3 != 0 { return 4 }
                if hash(x, alt) < 1800 { return min(tone + 1, 4) }          // pitting
                return tone
            }
            a -= thick
        }
        return 3
    }
}
