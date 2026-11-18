import Testing
import Foundation
@testable import RaceCore

struct TerrainTests {
    let track = Track(lengthCells: 40, pieces: [.init(kind: .smallHill, cell: 6), .init(kind: .rockRamp, cell: 10),
                                                .init(kind: .bumps, cell: 15), .init(kind: .mud, cell: 20, lane: 0)])
    let t: Terrain

    init() { t = Terrain(track: track) }

    @Test func lengthAndFinish() { #expect(t.length == 160); #expect(t.finishX == 152) }
    @Test func flatWhereNoTerrain() { for x in [-5.0, 0, 10, 82, 159, 200] { #expect(t.height(at: x) == 0); #expect(t.slope(at: x) == 0) } }
    @Test func smallHillProfile() {            // spans x 24...32, crest at 28
        #expect(abs(t.height(at: 28) - 1.5) < 1e-9); #expect(abs(t.height(at: 24)) < 1e-9); #expect(abs(t.height(at: 32)) < 1e-9)
        #expect(t.slope(at: 26) > 0); #expect(t.slope(at: 30) < 0); #expect(abs(t.slope(at: 28)) < 1e-9)
    }
    @Test func rockRampProfile() {             // spans x 40...52, peak at 40 + 0.85*12 = 50.2
        #expect(abs(t.height(at: 50.2) - 2.5) < 1e-9); #expect(abs(t.height(at: 45.1) - 1.25) < 1e-9)
        #expect(t.slope(at: 45) > 0); #expect(t.slope(at: 51) < -0.9)
    }
    @Test func bumpsProfile() {                // spans x 60...72, crests at 62, 66, 70
        for x in [62.0, 66, 70] { #expect(abs(t.height(at: x) - 0.5) < 1e-9) }
        for x in [60.0, 64, 68, 72] { #expect(abs(t.height(at: x)) < 1e-9) }
    }
    @Test func slopeMatchesNumericDerivative() {
        for x in stride(from: 24.5, to: 72, by: 0.37) where abs(x - 50.2) > 0.01 {
            let numeric = atan((t.height(at: x + 1e-5) - t.height(at: x - 1e-5)) / 2e-5)
            #expect(abs(t.slope(at: x) - numeric) < 1e-4)
        }
    }
}
