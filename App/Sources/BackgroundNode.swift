import SpriteKit

/// The painted sky and two strips of scenery, drawn behind the track. A child of the camera: the sky
/// stays put, the strips slide by more slowly than the track, and each strip stands on its own plain
/// that comes into view when the camera rises.
@MainActor
final class BackgroundNode: SKNode {
    /// Share of the camera's rise that the sky moves down by, and the most it can move (the image
    /// has this many spare rows above a 360-point view).
    private static let skyDrop: CGFloat = 0.1
    private static let skyMaxDrop: CGFloat = 40
    /// Added to a strip's sideways parallax to get its share of the camera's rise.
    private static let riseBase: CGFloat = 0.15
    private static let floorHeight: CGFloat = 400

    private struct Strip {
        let info: ArtInfo.Layer
        let tiles: [SKSpriteNode]
        let floor: SKSpriteNode
    }

    private let sky = SKSpriteNode(texture: Art.texture("backdrop"))
    private var strips: [Strip] = []

    override init() {
        super.init()
        sky.anchorPoint = CGPoint(x: 0.5, y: 0)
        sky.zPosition = 0
        addChild(sky)
        for (z, name) in ["mid", "near"].enumerated() {
            guard let info = ArtInfo.shared.layers[name] else { continue }
            let texture = Art.texture("layer-\(name)")
            let tiles = (0..<2).map { _ in SKSpriteNode(texture: texture) }
            let floor = SKSpriteNode(color: Art.colour(info.floor),
                                     size: CGSize(width: 2000, height: BackgroundNode.floorHeight))
            floor.anchorPoint = CGPoint(x: 0.5, y: 1)
            for node in tiles + [floor] {
                node.zPosition = CGFloat(z + 1)
                addChild(node)
            }
            tiles.forEach { $0.anchorPoint = .zero }
            strips.append(Strip(info: info, tiles: tiles, floor: floor))
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `cameraX` is the camera's scene x, `rise` how far it sits above its resting height, and
    /// `visible` the size of the scene area on screen, all in scene points.
    func update(cameraX: CGFloat, rise: CGFloat, visible: CGSize) {
        let bottom = -visible.height / 2
        let left = -visible.width / 2
        sky.position = CGPoint(x: 0, y: bottom - min(max(rise * BackgroundNode.skyDrop, 0), BackgroundNode.skyMaxDrop))
        for strip in strips {
            let width = strip.tiles[0].size.width
            let parallax = CGFloat(strip.info.parallax)
            var offset = (cameraX * parallax).truncatingRemainder(dividingBy: width)
            if offset < 0 { offset += width }
            let y = bottom + CGFloat(strip.info.baseAboveBottom - strip.info.floorRows)
                - rise * (BackgroundNode.riseBase + parallax)
            for (i, tile) in strip.tiles.enumerated() {
                tile.position = CGPoint(x: left - offset + CGFloat(i) * width, y: y)
            }
            strip.floor.position = CGPoint(x: 0, y: y)
        }
    }
}
