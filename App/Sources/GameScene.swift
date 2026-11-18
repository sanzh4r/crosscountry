import RaceCore
import SpriteKit
import UIKit

/// Owns the race and its fixed-step clock, steps it from `update(_:)`, and draws it.
@MainActor
final class GameScene: SKScene {
    static let sceneSize = CGSize(width: 480, height: 270)
    static let pointsPerMetre: CGFloat = 12
    /// Height 0 sits this far above the bottom edge of the 480×270 scene when the bike is at height 0.
    private static let groundBaseline: CGFloat = 60
    /// Fraction of the visible width between the left edge and the bike.
    private static let bikeScreenFraction: CGFloat = 0.3
    /// Rate (1/s) at which the camera closes the vertical gap to the bike.
    private static let cameraVerticalEasing = 4.0
    /// Frame gaps longer than this (the view was paused or the app was in the background) count as zero.
    private static let maxFrameGap = 0.25

    private var race: Race
    private var clock = FixedStepClock()
    private var lastUpdateTime: TimeInterval?

    private let terrainNode: TerrainNode
    private let bikeNode = BikeNode(pointsPerMetre: GameScene.pointsPerMetre)
    private let cameraNode = SKCameraNode()
    /// Camera child scaled so that one unit is one view point; holds the HUD and buttons.
    private let overlay = SKNode()
    private let hud = HUDNode()
    private let input = InputSource()

    private var laidOutViewSize = CGSize.zero
    private var laidOutInsets = UIEdgeInsets.zero
    /// Visible scene width (in scene points) for the current view; 480 until the view is known.
    private var visibleWidth = GameScene.sceneSize.width

    /// The current race tuning.
    var tuning: Tuning { race.tuning }

    override init() {
        race = Race(track: .prototype, tuning: Tuning())
        terrainNode = TerrainNode(terrain: race.terrain, pointsPerMetre: GameScene.pointsPerMetre)
        super.init(size: GameScene.sceneSize)
        scaleMode = .aspectFill
        backgroundColor = SKColor(red: 0.45, green: 0.62, blue: 0.80, alpha: 1)

        terrainNode.zPosition = 0
        bikeNode.zPosition = 1
        overlay.zPosition = 10
        addChild(terrainNode)
        addChild(bikeNode)
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.addChild(overlay)
        overlay.addChild(hud)
        input.attach(to: overlay)
        syncNodes(snapCamera: true, elapsed: 0)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts a fresh race on the prototype track with `tuning`; resets the clock and the camera.
    func restart(with tuning: Tuning) {
        race = Race(track: .prototype, tuning: tuning)
        clock = FixedStepClock()
        lastUpdateTime = nil
        syncNodes(snapCamera: true, elapsed: 0)
    }

    override var isPaused: Bool {
        didSet { if oldValue && !isPaused { lastUpdateTime = nil } }
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        lastUpdateTime = nil
        layoutOverlayIfNeeded()
    }

    override func update(_ currentTime: TimeInterval) {
        layoutOverlayIfNeeded()
        // The first frame after start, restart or un-pausing counts as zero elapsed.
        var elapsed = lastUpdateTime.map { currentTime - $0 } ?? 0
        if elapsed > GameScene.maxFrameGap { elapsed = 0 }
        lastUpdateTime = currentTime

        input.showsRestartButton = race.bike.finished
        input.poll()
        if input.restartPressed {
            restart(with: race.tuning)
            return
        }
        let steps = clock.advance(by: elapsed)
        for _ in 0..<steps { race.step(input.current) }
        syncNodes(snapCamera: false, elapsed: Double(steps) * Race.dt)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        input.touchesChanged(touches, in: overlay)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        input.touchesChanged(touches, in: overlay)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        input.touchesEnded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        input.touchesEnded(touches)
    }

    // MARK: Drawing

    /// Moves the bike, camera and HUD to the race state. `elapsed` is simulated seconds since the last sync.
    private func syncNodes(snapCamera: Bool, elapsed: Double) {
        bikeNode.update(with: race.bike)
        hud.update(with: race)

        let m = GameScene.pointsPerMetre
        let offsetX = visibleWidth * (0.5 - GameScene.bikeScreenFraction)
        let maxCameraX = terrainNode.drawnEndX * m - visibleWidth / 2
        let targetY = race.bike.y * m + size.height / 2 - GameScene.groundBaseline
        var y = targetY
        if !snapCamera {
            let blend = 1 - exp(-GameScene.cameraVerticalEasing * elapsed)
            y = cameraNode.position.y + (targetY - cameraNode.position.y) * blend
        }
        cameraNode.position = CGPoint(x: min(race.bike.x * m + offsetX, maxCameraX), y: y)
    }

    /// Scales the overlay to view points and lays out the HUD and buttons whenever the view's size
    /// or safe area changes.
    private func layoutOverlayIfNeeded() {
        guard let view else { return }
        let viewSize = view.bounds.size
        let insets = view.safeAreaInsets
        guard viewSize.width > 0, viewSize.height > 0,
              viewSize != laidOutViewSize || insets != laidOutInsets else { return }
        laidOutViewSize = viewSize
        laidOutInsets = insets

        // .aspectFill: one scene point is `scale` view points.
        let scale = max(viewSize.width / size.width, viewSize.height / size.height)
        visibleWidth = viewSize.width / scale
        overlay.setScale(1 / scale)
        hud.layout(viewSize: viewSize, insets: insets)
        input.layout(viewSize: viewSize, insets: insets)
    }
}
