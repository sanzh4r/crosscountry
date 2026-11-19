import RaceCore
import SpriteKit

/// Dust, exhaust flame, smoke and landing puffs: small square "pixels" that fly, shrink and vanish.
/// Lives in the world, in front of the bike.
@MainActor
final class EffectsNode: SKNode {
    private struct Particle {
        let node: SKSpriteNode
        var velocity: CGVector
        var gravity: CGFloat
        var age = 0.0
        let life: Double
        let size: CGFloat
    }

    private static let maxParticles = 320
    private static let dustGravity: CGFloat = -170
    /// Dust and flame particles per second (dust is per metre/second of bike speed).
    private static let dustPerSpeed = 3.5
    private static let boostDustFactor = 2.0
    private static let flameRate = 110.0
    private static let smokeRate = 16.0
    private static let minDustSpeed = 2.5

    private let dustColours: [SKColor]
    private let flameColours: [SKColor]
    private let smokeColours: [SKColor]
    private var particles: [Particle] = []
    private var dustDebt = 0.0, flameDebt = 0.0, smokeDebt = 0.0

    override init() {
        let art = ArtInfo.shared
        // Lighter and darker than the sand they fly over, so they read against it.
        dustColours = [art.sun, art.sand[0], art.sand[0], art.sand[3]].map(Art.colour)
        flameColours = [art.sun, art.sun, art.rock[0], art.rock[1]].map(Art.colour)
        smokeColours = [art.rock[4], art.sky, art.rock[3]].map(Art.colour)
        super.init()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func clear() {
        particles.forEach { $0.node.removeFromParent() }
        particles.removeAll()
    }

    /// Continuous effects for this frame. Points are scene points; `bikeVelocity` is scene points/s.
    func ride(bike: BikeState, rearWheel: CGPoint, exhaust: CGPoint, bikeVelocity: CGVector,
              boosting: Bool, elapsed: Double) {
        let stalled = bike.stallRemaining > 0
        // Spread this frame's particles back along the path the bike just covered, so a slow
        // frame leaves a trail rather than a clump.
        func trailing(_ point: CGPoint) -> CGPoint {
            let back = CGFloat.random(in: 0...1) * CGFloat(elapsed)
            return CGPoint(x: point.x - bikeVelocity.dx * back, y: point.y - bikeVelocity.dy * back)
        }
        if bike.phase == .grounded, bike.speed > EffectsNode.minDustSpeed {
            dustDebt += bike.speed * EffectsNode.dustPerSpeed * (boosting ? EffectsNode.boostDustFactor : 1) * elapsed
            while dustDebt >= 1 {
                dustDebt -= 1
                emit(at: trailing(rearWheel), velocity: CGVector(dx: .random(in: -90 ... -10), dy: .random(in: 30...130)),
                     colours: dustColours, size: .random(in: 2...5), life: .random(in: 0.35...0.8),
                     gravity: EffectsNode.dustGravity)
            }
        }
        if boosting, !stalled, !isCrashed(bike) {
            flameDebt += EffectsNode.flameRate * elapsed
            while flameDebt >= 1 {
                flameDebt -= 1
                emit(at: trailing(CGPoint(x: exhaust.x, y: exhaust.y + .random(in: -1...1))),
                     velocity: CGVector(dx: bikeVelocity.dx * 0.6 + .random(in: -30...0),
                                        dy: bikeVelocity.dy * 0.6 + .random(in: -10...10)),
                     colours: flameColours, size: .random(in: 3...5), life: .random(in: 0.12...0.3), gravity: 0)
            }
        }
        if stalled {
            smokeDebt += EffectsNode.smokeRate * elapsed
            while smokeDebt >= 1 {
                smokeDebt -= 1
                emit(at: CGPoint(x: exhaust.x + .random(in: 8...22), y: exhaust.y + .random(in: -4...4)),
                     velocity: CGVector(dx: bikeVelocity.dx * 0.4 + .random(in: -12...12), dy: .random(in: 25...55)),
                     colours: smokeColours, size: .random(in: 3...4), life: .random(in: 0.6...1.1), gravity: 25)
            }
        }
        advance(by: elapsed)
    }

    /// A burst of dust where the bike came down; `impact` is the downward speed in m/s.
    func landing(at point: CGPoint, impact: Double, crashed: Bool) {
        let count = crashed ? 34 : min(max(Int(impact * 1.6), 5), 22)
        let reach = CGFloat(crashed ? 150 : 50 + impact * 6)
        for _ in 0..<count {
            emit(at: CGPoint(x: point.x + .random(in: -14...14), y: point.y + 1),
                 velocity: CGVector(dx: .random(in: -reach...reach), dy: .random(in: 20...(crashed ? 150 : 95))),
                 colours: dustColours, size: .random(in: 2...4), life: .random(in: 0.35...0.8),
                 gravity: EffectsNode.dustGravity)
        }
    }

    private func isCrashed(_ bike: BikeState) -> Bool {
        if case .crashed = bike.phase { return true }
        return false
    }

    private func emit(at point: CGPoint, velocity: CGVector, colours: [SKColor], size: CGFloat,
                      life: Double, gravity: CGFloat) {
        guard particles.count < EffectsNode.maxParticles, let colour = colours.randomElement() else { return }
        let side = size.rounded()
        let node = SKSpriteNode(color: colour, size: CGSize(width: side, height: side))
        node.position = point
        addChild(node)
        particles.append(Particle(node: node, velocity: velocity, gravity: gravity, life: life, size: side))
    }

    private func advance(by elapsed: Double) {
        guard elapsed > 0 else { return }
        let dt = CGFloat(elapsed)
        for i in particles.indices.reversed() {
            particles[i].age += elapsed
            let p = particles[i]
            if p.age >= p.life {
                p.node.removeFromParent()
                particles.remove(at: i)
                continue
            }
            particles[i].velocity.dy += p.gravity * dt
            p.node.position.x += p.velocity.dx * dt
            p.node.position.y += p.velocity.dy * dt
            // Shrink in whole pixels rather than fade, to stay pixel art.
            let side = max(1, (p.size * CGFloat(1 - p.age / p.life * 0.8)).rounded())
            p.node.size = CGSize(width: side, height: side)
        }
    }
}
