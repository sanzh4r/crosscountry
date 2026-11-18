import RaceCore
import SpriteKit

/// The ground as one filled shape, sampled every 0.25 m, plus a post marking the finish line.
@MainActor
final class TerrainNode: SKNode {
    static let sampleSpacing = 0.25            // metres
    static let leadIn = 50.0                   // metres drawn before x = 0
    static let runOut = 200.0                  // metres drawn past the track end (a finished bike coasts on)
    static let fillDepth: CGFloat = 400        // points below height 0, well under the bottom edge

    /// World x (metres) where the drawn ground ends.
    let drawnEndX: Double

    init(terrain: Terrain, pointsPerMetre: CGFloat) {
        let startX = -TerrainNode.leadIn
        drawnEndX = terrain.length + TerrainNode.runOut
        super.init()

        let path = CGMutablePath()
        path.move(to: CGPoint(x: startX * pointsPerMetre, y: -TerrainNode.fillDepth))
        let sampleCount = Int(((drawnEndX - startX) / TerrainNode.sampleSpacing).rounded())
        for i in 0...sampleCount {
            let x = startX + Double(i) * TerrainNode.sampleSpacing
            path.addLine(to: CGPoint(x: x * pointsPerMetre, y: terrain.height(at: x) * pointsPerMetre))
        }
        path.addLine(to: CGPoint(x: drawnEndX * pointsPerMetre, y: -TerrainNode.fillDepth))
        path.closeSubpath()

        let ground = SKShapeNode(path: path)
        ground.fillColor = SKColor(red: 0.82, green: 0.70, blue: 0.48, alpha: 1)
        ground.strokeColor = .clear
        ground.lineWidth = 0
        addChild(ground)

        let postHeight: CGFloat = 60
        let post = SKSpriteNode(color: .white, size: CGSize(width: 3, height: postHeight))
        post.anchorPoint = CGPoint(x: 0.5, y: 0)
        post.position = CGPoint(x: terrain.finishX * pointsPerMetre,
                                y: terrain.height(at: terrain.finishX) * pointsPerMetre)
        addChild(post)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }
}
