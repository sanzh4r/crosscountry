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
    /// boost top speed (the bike drops back so more of the track ahead shows, but stays clear of the
    /// left-hand control).
    private static let bikeScreenFraction: (slow: CGFloat, fast: CGFloat) = (0.34, 0.24)
    /// Rate (1/s) at which the bike's place on screen follows its speed.
    private static let lookAheadEasing = 1.5
    /// Screen shake: scene points per m/s of landing speed, the cap for a landing, the strength of
    /// a crash, and the rate (1/s) at which it dies away.
    private static let shakePerImpact: CGFloat = 0.3
    private static let maxLandingShake: CGFloat = 4
    private static let crashShake: CGFloat = 7
    private static let shakeDecay = 9.0
    /// Landings slower than this (m/s downward) raise no dust and no shake.
    private static let minImpact = 3.0
    /// Rate (1/s) at which the camera closes the vertical gap to the bike.
    private static let cameraVerticalEasing = 4.0
    /// Frame gaps longer than this (the view was paused or the app was in the background) count as zero.
    private static let maxFrameGap = 0.25

    /// The track being raced.
    private static let track = Track.duskRun

    private var race: Race
    private var clock = FixedStepClock()
    private var lastUpdateTime: TimeInterval?
    private var lastFrameGap = 0.0

    private let terrainNode: TerrainNode
    private let background = BackgroundNode()
    /// Dust, flame and smoke for each bike in `race.bikes`, the player first.
    private let effects = (0...GameScene.rivalSkills.count).map { _ in EffectsNode() }
    /// Current screen-shake strength in scene points; dies away quickly.
    private var shake: CGFloat = 0
    /// What each bike was asked to do on the latest step.
    private var lastInputs: [RiderInput] = []
    private let bikeNode = BikeNode(pointsPerMetre: GameScene.pointsPerMetre)
    /// Computer riders for `race.bikes[1...]`, and their sprites.
    private static let rivalSkills: [Rival.Skill] = [.rookie, .steady, .sharp]
    private var rivals: [Rival] = []
    private let rivalNodes: [BikeNode] = (1...GameScene.rivalSkills.count).map {
        BikeNode(pointsPerMetre: GameScene.pointsPerMetre, style: $0)
    }
    /// Changes on every restart so the rivals do not ride the same race twice.
    private var raceNumber: UInt64 = 0
    private let sound = SoundPlayer()
    private let cameraNode = SKCameraNode()
    /// Camera child scaled so that one unit is one view point; holds the HUD and buttons.
    private let overlay = SKNode()
    private let hud = HUDNode()
    private let input = InputSource()
    /// Title, countdown and results; a child of the overlay scaled so one unit is one art pixel.
    private let menu = MenuNode()

    private enum Mode { case title, countdown, racing, results }
    private var mode = Mode.title
    private let pauseButton = PauseButton()
    /// True while the player has the race stopped behind the pause panel.
    private var held = false
    /// Pausing is offered from the countdown until the player crosses the line.
    private var canPause: Bool { (mode == .countdown || mode == .racing) && !race.bike.finished && !held }
    /// View points between the pause button and the tuning button to its right, which is 44 wide
    /// and 8 from the corner.
    private static let pauseButtonGap: CGFloat = 10
    /// Seconds for each number of the start countdown, how long "GO!" stays up, and the pause
    /// between crossing the line and the results panel.
    private static let countdownStep = 0.8
    private static let goTime = 0.8
    private static let resultsPause = 1.6
    private var countdown = 0.0
    private var goRemaining = 0.0
    private var resultsDelay = 0.0
    private var beatBest = false
    private static let bestTimeKey = "bestTime.duskRun"
    /// The player's fastest finish on this track, kept between launches.
    private var bestTime: Double? {
        get { UserDefaults.standard.object(forKey: GameScene.bestTimeKey) as? Double }
        set { UserDefaults.standard.set(newValue, forKey: GameScene.bestTimeKey) }
    }

    private var laidOutViewSize = CGSize.zero
    private var laidOutInsets = UIEdgeInsets.zero
    /// Visible scene area (in scene points) for the current view; the whole scene until the view is known.
    private var visibleSize = GameScene.sceneSize
    private var bikeFraction = GameScene.bikeScreenFraction.slow
    /// The camera's height before any shake is added.
    private var cameraHeight: CGFloat = 0

    /// The current race tuning.
    var tuning: Tuning { race.tuning }

    override init() {
        race = Race(track: GameScene.track, tuning: Tuning(), rivals: GameScene.rivalSkills.count)
        terrainNode = TerrainNode(track: GameScene.track, terrain: race.terrain, pointsPerMetre: GameScene.pointsPerMetre)
        super.init(size: GameScene.sceneSize)
        scaleMode = .aspectFill
        backgroundColor = Art.colour(ArtInfo.shared.sky)

        terrainNode.zPosition = 0
        bikeNode.zPosition = 1
        for node in effects {
            node.zPosition = 2
            addChild(node)
        }
        overlay.zPosition = 10
        addChild(terrainNode)
        addChild(bikeNode)
        for node in rivalNodes { addChild(node) }
        seatRivals()
        addChild(cameraNode)
        camera = cameraNode
        background.zPosition = -100
        cameraNode.addChild(background)
        cameraNode.addChild(overlay)
        overlay.addChild(hud)
        input.attach(to: overlay)
        menu.zPosition = 5
        overlay.addChild(menu)
        pauseButton.alpha = 0.72
        overlay.addChild(pauseButton)
        NotificationCenter.default.addObserver(self, selector: #selector(pause),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        enterTitle()
        #if DEBUG
        applySnapshotMode()
        #endif
        syncNodes(snapCamera: true, elapsed: 0)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets up a fresh race with `tuning` and resets the clock and the camera. From the title screen it
    /// waits there; otherwise the start countdown begins.
    func restart(with tuning: Tuning) {
        race = Race(track: GameScene.track, tuning: tuning, rivals: GameScene.rivalSkills.count)
        raceNumber += 1
        seatRivals()
        clock = FixedStepClock()
        lastUpdateTime = nil
        held = false
        menu.hidePause()
        effects.forEach { $0.clear() }
        sound.raceStarted()
        shake = 0
        if mode != .title { beginCountdown() }
        syncNodes(snapCamera: true, elapsed: 0)
    }

    // MARK: Race flow

    private func enterTitle() {
        mode = .title
        input.controlsVisible = false
        hud.isHidden = true
        menu.showTitle(best: bestTime, soundOn: sound.isOn)
    }

    private func beginCountdown() {
        mode = .countdown
        countdown = 3 * GameScene.countdownStep
        goRemaining = 0
        input.controlsVisible = true
        hud.isHidden = false
        menu.showCountdown("3")
        sound.play(.count)
    }

    private func advanceCountdown(by elapsed: Double) {
        let shown = Int((countdown / GameScene.countdownStep).rounded(.up))
        countdown -= elapsed
        if countdown <= 0 {
            mode = .racing
            clock = FixedStepClock()
            goRemaining = GameScene.goTime
            menu.showCountdown("GO!")
            sound.play(.go)
        } else {
            let now = Int((countdown / GameScene.countdownStep).rounded(.up))
            if now != shown {
                menu.showCountdown("\(now)")
                sound.play(.count)
            }
        }
    }

    private func showResults() {
        mode = .results
        input.controlsVisible = false
        menu.showResults(for: race, best: bestTime, newBest: beatBest)
    }

    /// Stops the race behind the pause panel; also called when the app leaves the foreground.
    @objc private func pause() {
        guard canPause else { return }
        held = true
        input.controlsVisible = false
        menu.showPause()
        sound.setSilenced(true)
    }

    private func resume() {
        held = false
        input.controlsVisible = true
        menu.hidePause()
        lastUpdateTime = nil
    }

    private func perform(_ action: MenuNode.Action) {
        switch action {
        case .resume:
            resume()
        case .start:
            beginCountdown()
        case .toggleSound:
            sound.isOn.toggle()
            menu.showTitle(best: bestTime, soundOn: sound.isOn)
        case .again:
            restart(with: race.tuning)
        case .title:
            mode = .title
            restart(with: race.tuning)
            enterTitle()
        }
    }

    private func seatRivals() {
        rivals = GameScene.rivalSkills.enumerated().map { i, skill in
            Rival(skill: skill, seed: raceNumber &* 1000 &+ UInt64(i) &+ 1)
        }
    }

    override var isPaused: Bool {
        didSet {
            if oldValue && !isPaused { lastUpdateTime = nil }
            sound.setSilenced(isPaused || held)
        }
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
        lastFrameGap = elapsed

        input.poll()
        menu.update(elapsed: elapsed)
        if input.restartPressed, mode != .title {
            restart(with: race.tuning)
            return
        }
        if input.pausePressed {
            if held { resume() } else { pause() }
        }
        pauseButton.isHidden = !canPause
        if held {
            #if DEBUG
            saveDueSnapshot(after: elapsed)
            #endif
            return
        }
        switch mode {
        case .title:
            if input.startPressed { beginCountdown() }
            syncNodes(snapCamera: false, elapsed: elapsed)
        case .countdown:
            advanceCountdown(by: elapsed)
            syncNodes(snapCamera: false, elapsed: elapsed)
        case .racing, .results:
            let steps = clock.advance(by: elapsed)
            for _ in 0..<steps {
                step(riderInput())
                input.laneChangeTaken()
            }
            if goRemaining > 0 {
                goRemaining -= elapsed
                if goRemaining <= 0, mode == .racing { menu.showCountdown(nil) }
            }
            if mode == .racing, race.bike.finished {
                resultsDelay -= elapsed
                if resultsDelay <= 0 { showResults() }
            }
            if mode == .results { menu.updateResults(for: race) }
            syncNodes(snapCamera: false, elapsed: Double(steps) * Race.dt)
        }
        #if DEBUG
        saveDueSnapshot(after: elapsed)
        #endif
    }

    /// What the player's bike is asked to do on the next step.
    private func riderInput() -> RiderInput {
        #if DEBUG
        if snapshotMode != nil {
            return RiderInput(gas: true, boost: race.time < 2.2 || (race.time > 4 && race.time < 6.5), lean: 0)
        }
        #endif
        return input.current
    }

    /// One simulation step, plus the dust for every landing or crash it caused and the shake for the player's.
    private func step(_ riderInput: RiderInput) {
        let before = race.bikes
        var inputs = [riderInput]
        for i in rivals.indices { inputs.append(rivals[i].input(for: i + 1, in: race)) }
        race.step(inputs)
        lastInputs = inputs
        playEvents(from: before[0], to: race.bikes[0])
        let m = GameScene.pointsPerMetre
        for (i, after) in race.bikes.enumerated() {
            guard before[i].phase == .airborne, after.phase != .airborne else { continue }
            var crashed = false
            if case .crashed = after.phase { crashed = true }
            let impact = -before[i].vy
            guard crashed || impact > GameScene.minImpact else { continue }
            effects[i].landing(at: CGPoint(x: after.x * m, y: after.y * m + BikeNode.laneRise(after.lane)),
                               impact: impact, crashed: crashed)
            guard i == 0 else { continue }
            sound.play(crashed ? .crash : .land, volume: crashed ? 1 : Float(min(0.35 + impact / 14, 1)))
            shake = max(shake, crashed ? GameScene.crashShake
                                       : min(CGFloat(impact) * GameScene.shakePerImpact, GameScene.maxLandingShake))
        }
    }

    /// Sounds for what changed on the player's bike in one step (landings are handled with their dust).
    private func playEvents(from before: BikeState, to after: BikeState) {
        if before.stallRemaining == 0, after.stallRemaining > 0 { sound.play(.stall) }
        if !before.finished, after.finished {
            sound.raceFinished(won: race.position(of: 0) == 1)
            resultsDelay = GameScene.resultsPause
            beatBest = bestTime.map { race.time < $0 } ?? true
            if beatBest { bestTime = race.time }
        }
        if after.targetLane != before.targetLane {
            sound.play(.lane, volume: 0.6)
        } else if after.laneCooldown > before.laneCooldown {
            // The lane was taken: the change was refused.
            sound.play(.bump)
        }
        func surface(_ bike: BikeState) -> PieceKind? {
            bike.phase == .grounded ? race.surface(at: bike.x, lane: Int(bike.lane.rounded())) : nil
        }
        let now = surface(after)
        if now != surface(before) {
            if now == .boostPad { sound.play(.pad) }
            if now == .mud { sound.play(.mud, volume: 0.8) }
        }
    }

    #if DEBUG
    // MARK: Snapshots (debug)

    /// Seconds since launch from the SNAPSHOT_AT environment variable, e.g. "2,6,11". When set, the view
    /// is saved to Documents at each time and the app then quits. SNAPSHOT_MODE picks what is shown:
    /// "race" (the default: the bike rides itself from the start), "title", "count" or "results".
    private var snapshotTimes: [Double] = (ProcessInfo.processInfo.environment["SNAPSHOT_AT"] ?? "")
        .split(separator: ",").compactMap { Double($0) }
    private var snapshotClock = 0.0
    private var snapshotMode: String? {
        let environment = ProcessInfo.processInfo.environment
        return environment["SNAPSHOT_AT"] == nil ? nil : environment["SNAPSHOT_MODE"] ?? "race"
    }

    private func applySnapshotMode() {
        switch snapshotMode {
        case "race":
            mode = .racing
            menu.hide()
            input.controlsVisible = true
            hud.isHidden = false
        case "count":
            beginCountdown()
        case "pause":
            beginCountdown()
            pause()
        case "results":
            // Start just before the line so the results panel comes up within seconds.
            var bike = BikeState()
            bike.x = race.terrain.finishX - 40
            race = Race(track: GameScene.track, tuning: race.tuning, bike: bike, rivals: GameScene.rivalSkills.count)
            mode = .racing
            menu.hide()
            hud.isHidden = false
        default:
            break
        }
    }

    private func saveDueSnapshot(after elapsed: Double) {
        snapshotClock += elapsed
        guard let due = snapshotTimes.first, snapshotClock >= due, let view,
              let image = view.texture(from: self)?.cgImage() else { return }
        snapshotTimes.removeFirst()
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent("snapshot-\(Int((due * 10).rounded())).png")
        try? UIImage(cgImage: image).pngData()?.write(to: url)
        print("snapshot", url.path, "fps", 1 / max(view.preferredFramesPerSecond == 0 ? 0.016 : lastFrameGap, 0.001))
        print("sound", sound.status)
        if snapshotTimes.isEmpty { exit(0) }
    }
    #endif

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if canPause, touches.contains(where: { pauseButton.hitTest($0.location(in: overlay)) }) {
            pause()
            return
        }
        if mode == .title || mode == .results || held {
            for touch in touches {
                if let action = menu.action(at: touch.location(in: menu)) {
                    perform(action)
                    return
                }
            }
        }
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
        bikeNode.update(with: race.bike, tuning: race.tuning, elapsed: elapsed)
        for (node, bike) in zip(rivalNodes, race.bikes.dropFirst()) {
            node.update(with: bike, tuning: race.tuning, elapsed: elapsed)
        }
        hud.update(with: race, elapsed: elapsed)
        sound.update(with: race.bike, input: lastInputs.first ?? RiderInput(), tuning: race.tuning,
                     engineOn: mode != .title, elapsed: elapsed)

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
            y = cameraHeight + (targetY - cameraHeight) * blend
        }
        let offsetX = visibleSize.width * (0.5 - bikeFraction)
        let maxCameraX = terrainNode.drawnEndX * m - visibleSize.width / 2
        let x = min(race.bike.x * m + offsetX, maxCameraX)
        // The shake moves only what the camera shows of the world; the remembered height stays clean.
        cameraHeight = y
        shake *= CGFloat(exp(-GameScene.shakeDecay * elapsed))
        let jolt = shake < 0.5 ? CGPoint.zero
            : CGPoint(x: (CGFloat.random(in: -1...1) * shake).rounded(), y: (CGFloat.random(in: -1...1) * shake).rounded())
        cameraNode.position = CGPoint(x: x + jolt.x, y: y + jolt.y)
        background.update(cameraX: x, rise: y - restY, visible: visibleSize)

        for (i, bike) in race.bikes.enumerated() {
            let angle = CGFloat(bike.angle)
            let base = CGPoint(x: bike.x * m, y: bike.y * m + BikeNode.laneRise(bike.lane))
            let rear = CGPoint(x: base.x - 20 * cos(angle), y: base.y - 20 * sin(angle) + 1)
            let exhaust = CGPoint(x: rear.x - 10 * cos(angle) - 13 * sin(angle),
                                  y: rear.y - 10 * sin(angle) + 13 * cos(angle))
            effects[i].ride(bike: bike, rearWheel: rear, exhaust: exhaust,
                            bikeVelocity: CGVector(dx: bike.vx * m, dy: bike.vy * m),
                            boosting: i < lastInputs.count && lastInputs[i].boost, elapsed: elapsed)
        }
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
        hud.layout(viewSize: viewSize, insets: insets, pixel: scale)
        input.layout(viewSize: viewSize, insets: insets, pixel: scale)
        pauseButton.setScale(scale)
        let half = CGFloat(PauseButton.width) * scale / 2
        pauseButton.position = CGPoint(x: viewSize.width / 2 - insets.right - 52 - GameScene.pauseButtonGap - half,
                                       y: viewSize.height / 2 - 30)
        menu.setScale(scale)
        menu.layout(size: visibleSize)
    }
}
