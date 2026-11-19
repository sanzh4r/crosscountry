import RaceCore
import SpriteKit
import UIKit

/// Owns the race and its fixed-step clock, steps it from `update(_:)`, and draws it.
@MainActor
final class GameScene: SKScene {
    static let sceneSize = CGSize(width: 640, height: 360)
    static let pointsPerMetre: CGFloat = 27
    /// Height 0 sits this far above the bottom of the visible area when the bike is at height 0.
    private static let groundBaseline: CGFloat = 88
    /// Fraction of the visible width between the left edge and the bike: standing still, and at
    /// boost top speed (the bike drops back so more of the track ahead shows).
    private static let bikeScreenFraction: (slow: CGFloat, fast: CGFloat) = (0.34, 0.2)
    /// Rate (1/s) at which the bike's place on screen follows its speed.
    private static let lookAheadEasing = 1.5
    /// Rate (1/s) at which the camera closes the vertical gap to the bike.
    private static let cameraVerticalEasing = 4.0
    /// Frame gaps longer than this (the view was paused or the app was in the background) count as zero.
    private static let maxFrameGap = 0.25

    private var race: Race
    private var clock = FixedStepClock()
    private var lastUpdateTime: TimeInterval?

    private let terrainNode: TerrainNode
    private let background = BackgroundNode()
    private let bikeNode = BikeNode(pointsPerMetre: GameScene.pointsPerMetre)
    private let cameraNode = SKCameraNode()
    /// Camera child scaled so that one unit is one view point; holds the HUD and buttons.
    private let overlay = SKNode()
    private let hud = HUDNode()
    private let input = InputSource()

    private var laidOutViewSize = CGSize.zero
    private var laidOutInsets = UIEdgeInsets.zero
    /// Visible scene area (in scene points) for the current view; the whole scene until the view is known.
    private var visibleSize = GameScene.sceneSize
    private var bikeFraction = GameScene.bikeScreenFraction.slow

    /// The current race tuning.
    var tuning: Tuning { race.tuning }

    override init() {
        race = Race(track: .prototype, tuning: Tuning())
        terrainNode = TerrainNode(track: .prototype, terrain: race.terrain, pointsPerMetre: GameScene.pointsPerMetre)
        super.init(size: GameScene.sceneSize)
        scaleMode = .aspectFill
        backgroundColor = Art.colour(ArtInfo.shared.sky)

        terrainNode.zPosition = 0
        bikeNode.zPosition = 1
        overlay.zPosition = 10
        addChild(terrainNode)
        addChild(bikeNode)
        addChild(cameraNode)
        camera = cameraNode
        background.zPosition = -100
        cameraNode.addChild(background)
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
        #if DEBUG
        if let demo = demoInput {
            for _ in 0..<steps { race.step(demo) }
            syncNodes(snapCamera: false, elapsed: Double(steps) * Race.dt)
            saveDueSnapshot()
            return
        }
        #endif
        for _ in 0..<steps { race.step(input.current) }
        syncNodes(snapCamera: false, elapsed: Double(steps) * Race.dt)
    }

    #if DEBUG
    // MARK: Snapshots (debug)

    /// Race times (seconds) from the SNAPSHOT_AT environment variable, e.g. "2,6,11". When set, the
    /// bike rides itself with the gas held and the view is saved to Documents at each time.
    private var snapshotTimes: [Double] = (ProcessInfo.processInfo.environment["SNAPSHOT_AT"] ?? "")
        .split(separator: ",").compactMap { Double($0) }
    private var demoInput: RiderInput? {
        ProcessInfo.processInfo.environment["SNAPSHOT_AT"] == nil ? nil : RiderInput(gas: true, boost: false, lean: 0)
    }

    private func saveDueSnapshot() {
        guard let due = snapshotTimes.first, race.time >= due, let view,
              let image = view.texture(from: self)?.cgImage() else { return }
        snapshotTimes.removeFirst()
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent("snapshot-\(Int(due)).png")
        try? UIImage(cgImage: image).pngData()?.write(to: url)
        print("snapshot", url.path)
        if snapshotTimes.isEmpty { exit(0) }
    }
    #endif

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
        let fractions = GameScene.bikeScreenFraction
        let pace = CGFloat(min(race.bike.speed / race.tuning.boostTopSpeed, 1))
        let targetFraction = fractions.slow + (fractions.fast - fractions.slow) * pace
        let restY = visibleSize.height / 2 - GameScene.groundBaseline
        let targetY = race.bike.y * m + restY
        var y = targetY
        if snapCamera {
            bikeFraction = targetFraction
        } else {
            bikeFraction += (targetFraction - bikeFraction) * (1 - exp(-GameScene.lookAheadEasing * elapsed))
            let blend = 1 - exp(-GameScene.cameraVerticalEasing * elapsed)
            y = cameraNode.position.y + (targetY - cameraNode.position.y) * blend
        }
        let offsetX = visibleSize.width * (0.5 - bikeFraction)
        let maxCameraX = terrainNode.drawnEndX * m - visibleSize.width / 2
        let x = min(race.bike.x * m + offsetX, maxCameraX)
        cameraNode.position = CGPoint(x: x, y: y)
        background.update(cameraX: x, rise: y - restY, visible: visibleSize)
        terrainNode.show(minX: x - visibleSize.width / 2, maxX: x + visibleSize.width / 2)
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
        visibleSize = CGSize(width: viewSize.width / scale, height: viewSize.height / scale)
        overlay.setScale(1 / scale)
        hud.layout(viewSize: viewSize, insets: insets)
        input.layout(viewSize: viewSize, insets: insets)
    }
}
