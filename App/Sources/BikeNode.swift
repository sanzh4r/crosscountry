import RaceCore
import SpriteKit

/// The rider sprite. The node's origin is the ground-contact point between the wheels, so rotating
/// by `bike.angle` keeps both wheels on the surface.
@MainActor
final class BikeNode: SKNode {
    /// The tyres sit this many pixels into the sand.
    private static let sink: CGFloat = 2
    /// Ride-loop frames shown per metre travelled, and the fastest the loop may run (frames/s).
    private static let framesPerMetre = 1.1
    private static let maxFrameRate = 22.0
    /// Crash: the share of the crash time spent tumbling, how many turns, and the height of the hop.
    private static let tumbleShare = 0.6
    private static let tumbleTurns = 2.0
    private static let tumbleHop: CGFloat = 26
    private static let blinkRate = 9.0
    private static let stalledTint = SKColor(white: 0.1, alpha: 1)

    private let pointsPerMetre: CGFloat
    private let frames: [SKTexture]
    private let sprite: SKSpriteNode
    private let restY: CGFloat
    private var framePhase = 0.0

    init(pointsPerMetre: CGFloat) {
        self.pointsPerMetre = pointsPerMetre
        frames = (0..<ArtInfo.shared.rideFrames).map { Art.texture("bike-\($0)") }
        sprite = SKSpriteNode(texture: frames[0])
        restY = sprite.size.height / 2 - BikeNode.sink
        super.init()
        sprite.position = CGPoint(x: 0, y: restY)
        addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `elapsed` is simulated seconds since the last update.
    func update(with bike: BikeState, tuning: Tuning, elapsed: Double) {
        position = CGPoint(x: bike.x * pointsPerMetre, y: bike.y * pointsPerMetre)
        zRotation = bike.angle
        sprite.colorBlendFactor = 0
        sprite.alpha = 1
        sprite.zRotation = 0
        sprite.position.y = restY

        if case .crashed(let remaining) = bike.phase {
            let progress = 1 - remaining / max(tuning.crashDuration, 0.01)
            let tumble = min(progress / BikeNode.tumbleShare, 1)
            let eased = 1 - (1 - tumble) * (1 - tumble)
            sprite.zRotation = -2 * .pi * BikeNode.tumbleTurns * eased
            sprite.position.y = restY + BikeNode.tumbleHop * abs(sin(.pi * 2 * eased)) * (1 - eased * 0.6)
            if tumble >= 1 {
                // Getting back on: blink until the crash time is over.
                sprite.alpha = Int(remaining * BikeNode.blinkRate) % 2 == 0 ? 1 : 0.35
            }
            return
        }
        if bike.stallRemaining > 0 {
            sprite.color = BikeNode.stalledTint
            sprite.colorBlendFactor = 0.35
        }
        framePhase += min(bike.speed * BikeNode.framesPerMetre, BikeNode.maxFrameRate) * elapsed
        framePhase.formTruncatingRemainder(dividingBy: Double(frames.count))
        sprite.texture = frames[Int(framePhase) % frames.count]
    }
}
