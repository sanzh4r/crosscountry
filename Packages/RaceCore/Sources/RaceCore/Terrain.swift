import Foundation

public struct Terrain: Sendable {
    private struct Segment: Sendable {
        let kind: PieceKind
        let start: Double
        let width: Double
    }

    private static let rampRiseFraction = 0.85
    private static let bumpCount = 3

    private let segments: [Segment]
    public let length: Double
    public let finishX: Double

    public init(track: Track) {
        precondition((try? track.validate()) != nil, "Terrain requires a valid track")
        length = Double(track.lengthCells) * Track.cellWidth
        finishX = length - 2 * Track.cellWidth
        segments = track.pieces
            .filter { $0.kind.isTerrain }
            .map { Segment(kind: $0.kind, start: Double($0.cell) * Track.cellWidth,
                           width: Double($0.kind.widthCells) * Track.cellWidth) }
            .sorted { $0.start < $1.start }
    }

    public func height(at x: Double) -> Double {
        guard let s = segment(at: x) else { return 0 }
        let h = s.kind.height
        let u = (x - s.start) / s.width
        switch s.kind {
        case .smallHill, .bigHill:
            return h * (1 - cos(2 * .pi * u)) / 2
        case .rockRamp:
            let r = Terrain.rampRiseFraction
            return u < r ? h * u / r : h * (1 - u) / (1 - r)
        case .bumps:
            let v = u * Double(Terrain.bumpCount)
            return h * (1 - cos(2 * .pi * v)) / 2
        case .mud, .boostPad:
            return 0
        }
    }

    public func slope(at x: Double) -> Double {
        guard let s = segment(at: x) else { return 0 }
        let h = s.kind.height
        let u = (x - s.start) / s.width
        let dhdu: Double
        switch s.kind {
        case .smallHill, .bigHill:
            dhdu = h * .pi * sin(2 * .pi * u)
        case .rockRamp:
            let r = Terrain.rampRiseFraction
            dhdu = u < r ? h / r : -h / (1 - r)
        case .bumps:
            let n = Double(Terrain.bumpCount)
            dhdu = h * .pi * n * sin(2 * .pi * u * n)
        case .mud, .boostPad:
            dhdu = 0
        }
        return atan(dhdu / s.width)
    }

    private func segment(at x: Double) -> Segment? {
        segments.first { x >= $0.start && x <= $0.start + $0.width }
    }
}
