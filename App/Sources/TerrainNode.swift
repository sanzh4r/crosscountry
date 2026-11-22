import RaceCore
import SpriteKit

/// The ground, painted pixel by pixel in chunks that are made as the camera reaches them, plus the
/// finish gate. One scene point is one art pixel. The track's top is drawn as a band seen from
/// above: three lanes, the far one highest, with mud and boost pads painted into their lane.
@MainActor
final class TerrainNode: SKNode {
    static let leadIn = 50.0                   // metres drawn before x = 0
    static let runOut = 200.0                  // metres drawn past the track end (a finished bike coasts on)
    private static let chunkWidth = 256        // pixels
    /// Pixels painted below height 0; the camera never shows more than its resting baseline.
    private static let depthBelow = 96
    /// The finish gate's own ground patch is sunk this far so the track hides it.
    private static let gateSink: CGFloat = 24

    /// World x (metres) where the drawn ground ends.
    let drawnEndX: Double

    private let terrain: Terrain
    private let pointsPerMetre: Double
    private let rockRanges: [ClosedRange<Double>]
    private let surfaces: [PlacedPiece]
    /// Half the height of the lane band: the middle lane's line is the terrain height itself.
    private static let bandHalf = 13
    private let padTone: [UInt8]
    private let topRow: Int
    private let sandTones: [[UInt8]]
    private let rockTones: [[UInt8]]
    private var chunks: [Int: SKSpriteNode] = [:]

    init(track: Track, terrain: Terrain, pointsPerMetre: CGFloat) {
        self.terrain = terrain
        self.pointsPerMetre = Double(pointsPerMetre)
        drawnEndX = terrain.length + TerrainNode.runOut
        rockRanges = track.pieces.filter { $0.kind == .rockRamp }.map {
            let start = Double($0.cell) * Track.cellWidth
            return start...(start + Double($0.kind.widthCells) * Track.cellWidth)
        }
        surfaces = track.pieces.filter { !$0.kind.isTerrain }
        padTone = ArtInfo.shared.sun.map(UInt8.init)
        let highest = PieceKind.allCases.map(\.height).max() ?? 0
        topRow = Int((highest * Double(pointsPerMetre)).rounded(.up)) + 4 + TerrainNode.bandHalf
        sandTones = ArtInfo.shared.sand.map { $0.map(UInt8.init) }
        rockTones = ArtInfo.shared.rock.map { $0.map(UInt8.init) }
        super.init()

        let gate = SKSpriteNode(texture: Art.texture("gate"))
        gate.anchorPoint = CGPoint(x: 0.5, y: 0)
        gate.position = CGPoint(x: terrain.finishX * pointsPerMetre,
                                y: terrain.height(at: terrain.finishX) * pointsPerMetre - TerrainNode.gateSink)
        gate.zPosition = -1
        addChild(gate)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Makes the chunks covering scene x `minX...maxX` (plus one spare each side) and drops the rest.
    func show(minX: CGFloat, maxX: CGFloat) {
        let w = CGFloat(TerrainNode.chunkWidth)
        let first = max(Int((minX / w).rounded(.down)) - 1,
                        Int((-TerrainNode.leadIn * pointsPerMetre / Double(w)).rounded(.down)))
        let last = min(Int((maxX / w).rounded(.down)) + 1,
                       Int((drawnEndX * pointsPerMetre / Double(w)).rounded(.up)) - 1)
        guard first <= last else { return }
        for index in first...last where chunks[index] == nil {
            let node = makeChunk(index)
            chunks[index] = node
            addChild(node)
        }
        for (index, node) in chunks where index < first - 2 || index > last + 2 {
            node.removeFromParent()
            chunks[index] = nil
        }
    }

    /// Colour of the track's top face at band row `row` (0 = near edge, `2 * bandHalf - 1` = far edge).
    private func bandColour(x: Int, row: Int, isRock: Bool, surfaces: [PlacedPiece]) -> [UInt8] {
        let tones = isRock ? rockTones : sandTones
        let rows = TerrainNode.bandHalf * 2
        let laneHeight = Double(rows) / Double(Track.laneCount)
        let lane = Track.laneCount - 1 - min(Int(Double(row) / laneHeight), Track.laneCount - 1)
        let inLane = row - Int((Double(Track.laneCount - 1 - lane) * laneHeight).rounded())
        if let piece = surfaces.first(where: { $0.lane == lane }), inLane >= 1, inLane < Int(laneHeight) {
            let local = x - Int(Double(piece.cell) * Track.cellWidth * pointsPerMetre)
            if piece.kind == .mud {
                // Dark, wet patch with a few lighter ripples.
                return (local + inLane * 3) % 11 == 0 ? sandTones[3] : sandTones[4]
            }
            // Boost pad: bright chevrons pointing along the track.
            let centre = Int(laneHeight) / 2
            let chevron = (local + abs(inLane - centre) * 2) % 12
            return chevron < 5 ? padTone : tones[1]
        }
        if row == rows - 1 { return tones[2] }                      // far edge
        if row == 0 { return tones[0] }                             // lit near lip
        // Dashed lines between the lanes.
        let onLine = (1..<Track.laneCount).contains { Int((Double($0) * laneHeight).rounded()) == row }
        if onLine && (x / 10) % 2 == 0 { return tones[2] }
        return (x * 7 + row * 13) % 23 == 0 ? tones[2] : tones[1]
    }

    private func makeChunk(_ index: Int) -> SKSpriteNode {
        let width = TerrainNode.chunkWidth
        let bottom = -TerrainNode.depthBelow
        let height = topRow - bottom
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for column in 0..<width {
            let wx = index * width + column
            let xm = Double(wx) / pointsPerMetre
            let middle = Int((terrain.height(at: xm) * pointsPerMetre).rounded())
            let half = TerrainNode.bandHalf
            // The band runs from the near edge (below the middle line) to the far edge (above it).
            let surface = middle - half
            let far = min(middle + half, topRow)
            let isRock = rockRanges.contains { $0.contains(xm) }
            let cell = Int((xm / Track.cellWidth).rounded(.down))
            let here = xm >= 0 ? surfaces.filter { cell >= $0.cell && cell < $0.cell + $0.kind.widthCells } : []
            guard far > bottom else { continue }
            for y in bottom..<far {
                let depth = surface - 1 - y
                var rgb = isRock ? rockTones[GroundPainter.rock(x: wx, depth: max(depth, 0), alt: y + 1)]
                                 : sandTones[GroundPainter.sand(x: wx, depth: max(depth, 0))]
                if y >= surface {
                    rgb = bandColour(x: wx, row: y - surface, isRock: isRock, surfaces: here)
                }
                let offset = ((topRow - 1 - y) * width + column) * 4
                pixels[offset] = rgb[0]
                pixels[offset + 1] = rgb[1]
                pixels[offset + 2] = rgb[2]
                pixels[offset + 3] = 255
            }
        }
        let node = SKSpriteNode(color: .clear, size: CGSize(width: width, height: height))
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            node.texture = texture
        }
        node.anchorPoint = .zero
        node.position = CGPoint(x: index * width, y: bottom)
        return node
    }
}
