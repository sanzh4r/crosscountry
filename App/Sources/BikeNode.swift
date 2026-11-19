import RaceCore
import SpriteKit

/// The rider sprite. The node's origin is the ground-contact point between the wheels, so rotating
/// by `bike.angle` keeps both wheels on the surface.
@MainActor
final class BikeNode: SKNode {
    /// The tyres sit this many pixels into the sand.
    private static let sink: CGFloat = 2
    private static let crashedTint = SKColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 1)
    private static let stalledTint = SKColor(red: 0.15, green: 0.40, blue: 0.95, alpha: 1)

    private let pointsPerMetre: CGFloat
    private let sprite = SKSpriteNode(texture: Art.texture("bike"))

    init(pointsPerMetre: CGFloat) {
        self.pointsPerMetre = pointsPerMetre
        super.init()
        sprite.anchorPoint = CGPoint(x: 0.5, y: BikeNode.sink / sprite.size.height)
        addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(with bike: BikeState) {
        position = CGPoint(x: bike.x * pointsPerMetre, y: bike.y * pointsPerMetre)
        zRotation = bike.angle
        if case .crashed = bike.phase {
            sprite.color = BikeNode.crashedTint
            sprite.colorBlendFactor = 0.6
        } else if bike.stallRemaining > 0 {
            sprite.color = BikeNode.stalledTint
            sprite.colorBlendFactor = 0.5
        } else {
            sprite.colorBlendFactor = 0
        }
    }
}
