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
    /// Standing still: below this speed (m/s) the rider puts a foot down, at this many frames/s.
    private static let standSpeed = 0.3
    private static let standFrameRate = 10.0
    private static let stalledTint = SKColor(white: 0.1, alpha: 1)
    /// Scene points from the node's origin back to where the rear tyre meets the ground; a wheelie
    /// turns the sprite about that point.
    static let rearWheelOffset: CGFloat = 20

    private let pointsPerMetre: CGFloat
    private let frames: [SKTexture]
    private let sprite: SKSpriteNode
    private let restY: CGFloat
    private let standFrames: [SKTexture]
    private var framePhase = 0.0
    /// 0 = riding pose, `standFrames.count` = foot planted.
    private var standPhase: Double

    /// Scene points between neighbouring lanes; the far lane is drawn highest.
    static let laneSpacing: CGFloat = 9

    /// How far above the middle lane a bike in `lane` is drawn.
    static func laneRise(_ lane: Double) -> CGFloat {
        ((CGFloat(Track.laneCount - 1) / 2 - CGFloat(lane)) * laneSpacing).rounded()
    }

    /// `style` 0 is the player's teal rider; 1...3 are the rivals' colours.
    init(pointsPerMetre: CGFloat, style: Int = 0) {
        self.pointsPerMetre = pointsPerMetre
        let suffix = style == 0 ? "" : "-r\(style)"
        frames = (0..<ArtInfo.shared.rideFrames).map { Art.texture("bike-\($0)\(suffix)") }
        standFrames = (0..<ArtInfo.shared.standFrames).map { Art.texture("stand-\($0)\(suffix)") }
        standPhase = Double(standFrames.count)   // a race starts with the foot down
        sprite = SKSpriteNode(texture: standFrames.last ?? frames[0])
        restY = sprite.size.height / 2 - BikeNode.sink
        super.init()
        sprite.position = CGPoint(x: 0, y: restY)
        addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `elapsed` is simulated seconds since the last update.
    func update(with bike: BikeState, tuning: Tuning, elapsed: Double) {
        position = CGPoint(x: bike.x * pointsPerMetre, y: bike.y * pointsPerMetre + BikeNode.laneRise(bike.lane))
        zPosition = 1 + CGFloat(bike.lane) * 0.1          // nearer lanes cover farther ones
        zRotation = bike.angle
        sprite.colorBlendFactor = 0
        sprite.alpha = 1
        // On the rear wheel: turn the sprite about the rear tyre's contact point.
        let lift = CGFloat(bike.wheelie), rear = BikeNode.rearWheelOffset
        sprite.zRotation = lift
        sprite.position = CGPoint(x: rear * (cos(lift) - 1) - restY * sin(lift), y: rear * sin(lift) + restY * cos(lift))

        if case .crashed(let remaining) = bike.phase {
            let progress = 1 - remaining / max(tuning.crashDuration, 0.01)
            let tumble = min(progress / BikeNode.tumbleShare, 1)
            let eased = 1 - (1 - tumble) * (1 - tumble)
            sprite.position.x = 0
            sprite.zRotation = -2 * .pi * BikeNode.tumbleTurns * eased
            sprite.position.y = restY + BikeNode.tumbleHop * abs(sin(.pi * 2 * eased)) * (1 - eased * 0.6)
            if tumble >= 1 {
                // Getting back on: blink until the crash time is over.
                standPhase = 0
                sprite.alpha = Int(remaining * BikeNode.blinkRate) % 2 == 0 ? 1 : 0.35
            }
            return
        }
        if bike.stallRemaining > 0 {
            sprite.color = BikeNode.stalledTint
            sprite.colorBlendFactor = 0.35
        }
        // Foot down when standing on the ground, back on the peg twice as fast when moving off.
        let standing = bike.phase == .grounded && bike.speed < BikeNode.standSpeed
        standPhase += (standing ? 1 : -2) * BikeNode.standFrameRate * elapsed
        standPhase = min(max(standPhase, 0), Double(standFrames.count))
        if standPhase > 0 {
            sprite.texture = standFrames[min(Int(standPhase), standFrames.count - 1)]
            return
        }
        framePhase += min(bike.speed * BikeNode.framesPerMetre, BikeNode.maxFrameRate) * elapsed
        framePhase.formTruncatingRemainder(dividingBy: Double(frames.count))
        sprite.texture = frames[Int(framePhase) % frames.count]
    }
}
