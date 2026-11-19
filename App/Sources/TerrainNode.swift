import RaceCore
import SpriteKit

/// The ground, painted pixel by pixel in chunks that are made as the camera reaches them, plus the
/// finish gate. One scene point is one art pixel.
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
        let highest = PieceKind.allCases.map(\.height).max() ?? 0
        topRow = Int((highest * Double(pointsPerMetre)).rounded(.up)) + 4
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

    private func makeChunk(_ index: Int) -> SKSpriteNode {
        let width = TerrainNode.chunkWidth
        let bottom = -TerrainNode.depthBelow
        let height = topRow - bottom
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for column in 0..<width {
            let wx = index * width + column
            let xm = Double(wx) / pointsPerMetre
            let surface = min(Int((terrain.height(at: xm) * pointsPerMetre).rounded()), topRow)
            let isRock = rockRanges.contains { $0.contains(xm) }
            guard surface > bottom else { continue }
            for y in bottom..<surface {
                let depth = surface - 1 - y
                let rgb = isRock ? rockTones[GroundPainter.rock(x: wx, depth: depth, alt: y + 1)]
                                 : sandTones[GroundPainter.sand(x: wx, depth: depth)]
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
