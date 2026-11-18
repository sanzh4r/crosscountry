import RaceCore
import SpriteKit

/// Rectangle body, two circle wheels and a rider block. The node's origin is the ground-contact
/// point, so rotating by `bike.angle` keeps both wheels on the surface.
@MainActor
final class BikeNode: SKNode {
    private static let wheelRadius = 0.35      // metres
    private static let wheelOffset = 0.7       // metres from the centre to each wheel hub
    private static let bodyLength = 1.8
    private static let bodyHeight = 0.35
    private static let bodyBottom = 0.45       // metres above the ground-contact line
    private static let riderSize = (width: 0.4, height: 0.7)
    private static let riderX = -0.15

    private static let normalColour = SKColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1)
    private static let crashedColour = SKColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 1)
    private static let stalledColour = SKColor(red: 0.15, green: 0.40, blue: 0.95, alpha: 1)

    private let pointsPerMetre: CGFloat
    private let body: SKShapeNode
    private let rider: SKShapeNode

    init(pointsPerMetre: CGFloat) {
        self.pointsPerMetre = pointsPerMetre
        let m = pointsPerMetre
        body = SKShapeNode(rect: CGRect(x: -BikeNode.bodyLength / 2 * m, y: BikeNode.bodyBottom * m,
                                        width: BikeNode.bodyLength * m, height: BikeNode.bodyHeight * m))
        rider = SKShapeNode(rect: CGRect(x: (BikeNode.riderX - BikeNode.riderSize.width / 2) * m,
                                         y: (BikeNode.bodyBottom + BikeNode.bodyHeight) * m,
                                         width: BikeNode.riderSize.width * m,
                                         height: BikeNode.riderSize.height * m))
        super.init()

        for shape in [body, rider] {
            shape.strokeColor = .clear
            shape.lineWidth = 0
            addChild(shape)
        }
        body.fillColor = BikeNode.normalColour
        rider.fillColor = SKColor(white: 0.25, alpha: 1)

        for side in [-1.0, 1.0] {
            let wheel = SKShapeNode(circleOfRadius: BikeNode.wheelRadius * m)
            wheel.fillColor = SKColor(white: 0.12, alpha: 1)
            wheel.strokeColor = .clear
            wheel.lineWidth = 0
            wheel.position = CGPoint(x: side * BikeNode.wheelOffset * m, y: BikeNode.wheelRadius * m)
            addChild(wheel)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(with bike: BikeState) {
        position = CGPoint(x: bike.x * pointsPerMetre, y: bike.y * pointsPerMetre)
        zRotation = bike.angle
        if case .crashed = bike.phase {
            body.fillColor = BikeNode.crashedColour
        } else if bike.stallRemaining > 0 {
            body.fillColor = BikeNode.stalledColour
        } else {
            body.fillColor = BikeNode.normalColour
        }
    }
}
