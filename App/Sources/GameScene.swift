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

    /// The tournament in progress, saved after every change.
    private var cup = GameScene.savedCup() {
        didSet { saveCup() }
    }
    private static let cupKey = "cup.dune"
    private static let cupsWonKey = "cupsWon.dune"
    private var cupsWon: Int {
        get { UserDefaults.standard.integer(forKey: GameScene.cupsWonKey) }
        set { if keepsRecords { UserDefaults.standard.set(newValue, forKey: GameScene.cupsWonKey) } }
    }
    /// Index of the track being ridden alone; nil in a cup race.
    private var solo: Int?
    /// A ride on the track open in the builder: alone to test it, or against the rivals.
    private var built: (track: Track, name: String, rivals: Bool, serial: Int)?
    private var builtRides = 0
    /// The race on screen: the built track, the solo track, or the cup's current race.
    private var round: Cup.Round {
        if let built {
            return Cup.Round(id: "built-\(built.serial)", name: built.name, track: built.track,
                             rivals: built.rivals ? [.rookie, .steady, .sharp] : [], targetTime: 0)
        }
        return solo.map { Cup.rounds[$0] } ?? cup.round
    }
    private var rivalCount: Int { built.map { $0.rivals ? GameScene.rivalCount : 0 } ?? (solo == nil ? GameScene.rivalCount : 0) }

    /// The player's own tracks, saved after every change, and the one open in the builder.
    private var library = GameScene.savedLibrary() {
        didSet { if keepsRecords { UserDefaults.standard.set(try? JSONEncoder().encode(library), forKey: GameScene.libraryKey) } }
    }
    private static let libraryKey = "tracks.built"
    private var editing: Int?
    private let builder = BuilderNode()
    private var drawnBuilderRevision = -1
    /// Marks the selected piece in the builder; lives in the world, above the piece.
    private let selectionMarker = SKSpriteNode(color: Art.colour(Palette.shared.dark), size: .zero)
    private let selectionBar = SKSpriteNode(color: Art.colour(Palette.shared.cream), size: .zero)
    /// Darken the start and finish stretches in the builder, where nothing can be placed.
    private let zoneShades = (0..<2).map { _ in SKSpriteNode(color: .black, size: .zero) }
    /// True on every screen where no race is on.
    private var inMenus: Bool { mode == .title || mode == .soloList || mode == .library || mode == .builder }
    private static let unlockedKey = "unlockedTracks.dune"
    /// How many tracks can be ridden solo: every one the cup has reached, for good.
    private var unlockedTracks: Int {
        min(max(UserDefaults.standard.integer(forKey: GameScene.unlockedKey), cup.current + 1), Cup.rounds.count)
    }
    /// The round whose track `terrainNode` draws.
    private var drawnRound = ""

    private var race: Race
    private var clock = FixedStepClock()
    private var lastUpdateTime: TimeInterval?
    private var lastFrameGap = 0.0

    private var terrainNode: TerrainNode
    private let background = BackgroundNode()
    /// Dust, flame and smoke for each bike in `race.bikes`, the player first.
    private let effects = (0...GameScene.rivalCount).map { _ in EffectsNode() }
    /// Current screen-shake strength in scene points; dies away quickly.
    private var shake: CGFloat = 0
    /// What each bike was asked to do on the latest step.
    private var lastInputs: [RiderInput] = []
    private let bikeNode = BikeNode(pointsPerMetre: GameScene.pointsPerMetre)
    /// Computer riders for `race.bikes[1...]`, and their sprites.
    private static let rivalCount = 3
    private var rivals: [Rival] = []
    private let rivalNodes: [BikeNode] = (1...GameScene.rivalCount).map {
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

    private enum Mode { case title, soloList, library, builder, countdown, racing, results, standings }
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
    /// The player's fastest finish on the current track, kept between launches.
    private var bestTime: Double? {
        get { built == nil ? UserDefaults.standard.object(forKey: "bestTime.\(round.id)") as? Double : nil }
        set { if keepsRecords, built == nil { UserDefaults.standard.set(newValue, forKey: "bestTime.\(round.id)") } }
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
        #if DEBUG
        if let skip = Int(ProcessInfo.processInfo.environment["SNAPSHOT_RACE"] ?? "") {
            // Snapshots can start at a later race, with made-up results for the earlier ones.
            var staged = Cup()
            for i in 0..<skip {
                staged.record([[2, 1, 3, 4], [1, 3, 4, 2], [3, 2, 1, 4], [1, 4, 2, 3]][i % 4])
                staged.advance()
            }
            cup = staged
        }
        #endif
        let round = cup.round
        race = Race(track: round.track, tuning: Tuning(), rivals: GameScene.rivalCount)
        terrainNode = TerrainNode(track: round.track, terrain: race.terrain, pointsPerMetre: GameScene.pointsPerMetre)
        drawnRound = round.id
        super.init(size: GameScene.sceneSize)
        if keepsRecords { UserDefaults.standard.set(unlockedTracks, forKey: GameScene.unlockedKey) }
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
        builder.zPosition = 4
        overlay.addChild(builder)
        selectionMarker.zPosition = 3
        selectionMarker.isHidden = true
        selectionBar.zPosition = 1
        selectionMarker.addChild(selectionBar)
        addChild(selectionMarker)
        for shade in zoneShades {
            shade.alpha = 0.4
            shade.zPosition = 3
            shade.anchorPoint = CGPoint(x: 0, y: 0.5)
            shade.isHidden = true
            addChild(shade)
        }
        pauseButton.alpha = 0.72
        overlay.addChild(pauseButton)
        NotificationCenter.default.addObserver(self, selector: #selector(pause),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        enterTitle()
        #if DEBUG
        applySnapshotMode()
        #endif
        if mode == .builder { syncBuilder(elapsed: 0) } else { syncNodes(snapCamera: true, elapsed: 0) }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets up a fresh race with `tuning` and resets the clock and the camera. From the title screen it
    /// waits there; otherwise the start countdown begins.
    func restart(with tuning: Tuning) {
        if mode == .library || mode == .builder {
            // No race to restart here; keep the tuning for the next one.
            race.tuning = tuning
            return
        }
        let round = self.round
        bikeNode.isHidden = false
        race = Race(track: round.track, tuning: tuning, rivals: rivalCount)
        hud.soloCaption = solo == nil ? "" : "BEAT \(HUDNode.format(time: round.targetTime))"
        if round.id != drawnRound {
            terrainNode.removeFromParent()
            terrainNode = TerrainNode(track: round.track, terrain: race.terrain, pointsPerMetre: GameScene.pointsPerMetre)
            terrainNode.zPosition = 0
            addChild(terrainNode)
            drawnRound = round.id
        }
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
        menu.showTitle(MenuNode.TitleInfo(raceNumber: cup.current + 1, trackName: cup.round.name, best: bestTime,
                                          cupsWon: cupsWon, cupUnderWay: cup.current > 0 || !cup.places.isEmpty,
                                          sound: sound.settingName))
    }

    private static func savedLibrary() -> TrackLibrary {
        guard let data = UserDefaults.standard.data(forKey: GameScene.libraryKey),
              let library = try? JSONDecoder().decode(TrackLibrary.self, from: data) else { return TrackLibrary() }
        return library
    }

    // MARK: Track builder

    private func showLibrary() {
        editing = nil
        built = nil
        if drawnRound == "builder" {
            // Put the race scene back behind the list.
            mode = .title
            restart(with: race.tuning)
        }
        mode = .library
        builder.isHidden = true
        selectionMarker.isHidden = true
        for shade in zoneShades { shade.isHidden = true }
        menu.showLibrary(library)
    }

    /// Opens saved track `index` in the builder.
    private func edit(_ index: Int) {
        guard library.tracks.indices.contains(index) else { return }
        let saved = library.tracks[index]
        editing = saved.id
        builder.begin(saved.track, name: saved.name)
        enterBuilder()
    }

    /// Shows the builder with whatever it was editing; also the way back from a test ride.
    private func enterBuilder() {
        mode = .builder
        built = nil
        held = false
        menu.hide()
        hud.isHidden = true
        input.controlsVisible = false
        builder.isHidden = false
        bikeNode.isHidden = true
        for node in rivalNodes { node.isHidden = true }
        effects.forEach { $0.clear() }
        sound.raceStarted()
        shake = 0
        drawnBuilderRevision = -1
        // Shade the closed stretches: everything before the build zone and everything after it.
        let m = GameScene.pointsPerMetre
        let cell = CGFloat(Track.cellWidth) * m
        let length = CGFloat(builder.track.lengthCells) * cell
        let lead = CGFloat(TerrainNode.leadIn) * m, tail = CGFloat(TerrainNode.runOut) * m
        let closed = CGFloat(Track.startZoneCells) * cell
        zoneShades[0].position = CGPoint(x: -lead, y: 0)
        zoneShades[0].size = CGSize(width: lead + closed, height: 1000)
        zoneShades[1].position = CGPoint(x: length - CGFloat(Track.finishZoneCells) * cell, y: 0)
        zoneShades[1].size = CGSize(width: CGFloat(Track.finishZoneCells) * cell + tail, height: 1000)
        for shade in zoneShades { shade.isHidden = false }
        syncBuilder(elapsed: 0)
    }

    private func perform(_ request: BuilderNode.Request) {
        switch request {
        case .exit:
            showLibrary()
        case .save:
            if let editing, library.save(builder.track, id: editing) { builder.markSaved() }
        case .delete:
            if let editing { library.delete(id: editing) }
            showLibrary()
        case .test, .race:
            builtRides += 1
            let name = library.tracks.first { $0.id == editing }?.name ?? "TRACK"
            built = (builder.track, name, request == .race, builtRides)
            builder.isHidden = true
            selectionMarker.isHidden = true
            for shade in zoneShades { shade.isHidden = true }
            mode = .racing
            restart(with: race.tuning)
        }
    }

    /// Draws the track being built and moves the camera to the builder's scroll position.
    private func syncBuilder(elapsed: Double) {
        let m = GameScene.pointsPerMetre
        builder.visibleMetres = Double(visibleSize.width / m)
        if builder.revision != drawnBuilderRevision {
            let track = builder.drawnTrack
            terrainNode.removeFromParent()
            terrainNode = TerrainNode(track: track, terrain: Terrain(track: track), pointsPerMetre: m)
            terrainNode.zPosition = 0
            addChild(terrainNode)
            drawnBuilderRevision = builder.revision
            drawnRound = "builder"
        }
        if let piece = builder.selectedPiece {
            let width = CGFloat(Double(piece.kind.widthCells) * Track.cellWidth) * m
            selectionMarker.size = CGSize(width: width + 4, height: 9)
            selectionBar.size = CGSize(width: width, height: 5)
            selectionMarker.position = CGPoint(x: CGFloat(Double(piece.cell) * Track.cellWidth) * m + width / 2,
                                               y: CGFloat(piece.kind.height) * m + 26)
            selectionMarker.isHidden = false
        } else {
            selectionMarker.isHidden = true
        }
        let restY = visibleSize.height / 2 - GameScene.groundBaseline
        let x = CGFloat(builder.scroll) * m
        cameraHeight = restY
        cameraNode.position = CGPoint(x: x, y: restY)
        background.update(cameraX: x, rise: 0, visible: visibleSize)
        terrainNode.show(minX: x - visibleSize.width / 2, maxX: x + visibleSize.width / 2)
        sound.update(with: race.bike, rivals: [], input: RiderInput(), tuning: race.tuning, engineOn: false,
                     elapsed: elapsed)
    }

    private static func savedCup() -> Cup {
        guard let data = UserDefaults.standard.data(forKey: GameScene.cupKey),
              let cup = try? JSONDecoder().decode(Cup.self, from: data), !cup.isFinished else { return Cup() }
        return cup
    }

    private func saveCup() {
        guard keepsRecords else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(cup), forKey: GameScene.cupKey)
    }

    /// False while taking debug snapshots, which ride made-up races that must not be saved.
    private var keepsRecords: Bool {
        #if DEBUG
        return snapshotMode == nil
        #else
        return true
        #endif
    }

    /// Every rider's place in the race on screen, the player first.
    private var places: [Int] { race.bikes.indices.map { race.position(of: $0) } }
    private var raceCaption: String {
        if let built { return "\(built.rivals ? "RACE" : "TEST RIDE") - \(built.name)" }
        return solo == nil ? "RACE \(cup.current + 1)/\(Cup.rounds.count) - \(round.name)" : "SOLO RUN - \(round.name)"
    }

    private func showSoloList() {
        mode = .soloList
        let open = unlockedTracks
        menu.showSoloList(Cup.rounds.enumerated().map { i, round in
            MenuNode.SoloRow(name: round.name, target: round.targetTime,
                             best: UserDefaults.standard.object(forKey: "bestTime.\(round.id)") as? Double,
                             unlocked: i < open)
        })
    }

    private func beginCountdown() {
        mode = .countdown
        countdown = 3 * GameScene.countdownStep
        goRemaining = 0
        input.controlsVisible = true
        hud.isHidden = false
        menu.showCountdown("3", caption: raceCaption)
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
                menu.showCountdown("\(now)", caption: raceCaption)
                sound.play(.count)
            }
        }
    }

    private func showResults() {
        mode = .results
        input.controlsVisible = false
        if built != nil {
            menu.showResults(for: race, best: nil, newBest: false, lastRace: false, built: true)
            return
        }
        if solo != nil {
            menu.showResults(for: race, best: bestTime, newBest: beatBest, lastRace: false, target: round.targetTime)
            return
        }
        // Banked now so that it survives the app being closed; "next" banks the final order.
        cup.record(places)
        menu.showResults(for: race, best: bestTime, newBest: beatBest, lastRace: cup.current == Cup.rounds.count - 1)
    }

    /// Banks the race, moves the cup on and shows the table; after the last race the cup starts afresh.
    private func showStandings() {
        guard solo == nil, built == nil else { return }
        cup.record(places)
        guard cup.canAdvance else { return }
        let raceNumber = cup.current + 1
        cup.advance()
        if keepsRecords { UserDefaults.standard.set(unlockedTracks, forKey: GameScene.unlockedKey) }
        mode = .standings
        menu.showStandings(cup, raceNumber: raceNumber, final: cup.isFinished)
        guard cup.isFinished else { return }
        if cup.standings[0] == 0 {
            cupsWon += 1
            sound.raceFinished(won: true)
        }
        cup = Cup()
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
            sound.cycleSetting()
            enterTitle()
        case .newCup:
            cup = Cup()
            restart(with: race.tuning)
            enterTitle()
        case .next:
            showStandings()
        case .soloList:
            showSoloList()
        case .solo(let index):
            solo = index
            restart(with: race.tuning)
        case .library:
            showLibrary()
        case .newTrack:
            menu.showLengthChoice()
        case .createTrack(let length):
            if library.create(length) != nil { edit(library.tracks.count - 1) }
        case .editTrack(let index):
            edit(index)
        case .nothing:
            break
        case .again, .continueCup:
            restart(with: race.tuning)
        case .title:
            if built != nil {
                // A ride on a built track ends back in the builder.
                enterBuilder()
                return
            }
            mode = .title
            solo = nil
            restart(with: race.tuning)
            enterTitle()
        }
    }

    private func seatRivals() {
        rivals = round.rivals.prefix(rivalCount).enumerated().map { i, skill in
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
        if input.restartPressed, !inMenus {
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
        case .soloList, .library:
            syncNodes(snapCamera: false, elapsed: elapsed)
        case .builder:
            syncBuilder(elapsed: elapsed)
        case .countdown:
            advanceCountdown(by: elapsed)
            syncNodes(snapCamera: false, elapsed: elapsed)
        case .racing, .results, .standings:
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
            if snapshotMode == "wheelie" { return RiderInput(gas: true, lean: race.bike.wheelie < 0.6 ? -1 : 0) }
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
            var crashed = false, wasCrashed = false
            if case .crashed = after.phase { crashed = true }
            if case .crashed = before[i].phase { wasCrashed = true }
            // A landing, or a bike that went over backwards out of a wheelie.
            let flipped = crashed && !wasCrashed && before[i].phase == .grounded
            guard flipped || (before[i].phase == .airborne && after.phase != .airborne) else { continue }
            let impact = flipped ? 0 : -before[i].vy
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
            // Brass for a win, or on a solo run for beating the target.
            sound.raceFinished(won: solo == nil ? race.position(of: 0) == 1 : race.time <= round.targetTime)
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
        case "race", "wheelie":
            mode = .racing
            menu.hide()
            input.controlsVisible = true
            hud.isHidden = false
        case "count":
            beginCountdown()
        case "sololist":
            showSoloList()
        case "library", "length":
            var sample = TrackLibrary()
            _ = sample.create(.short)
            _ = sample.create(.long)
            sample.save(Track(layout: "p1 _ h H _ m0 _ R _ b _ m1+m2 _ p0 _ H"), id: 1)
            library = sample
            showLibrary()
            if snapshotMode == "length" { menu.showLengthChoice() }
        case "builtrace":
            builder.begin(Track(layout: "h _ H _ m1 _ R"), name: "TRACK 1")
            enterBuilder()
            perform(BuilderNode.Request.race)
        case "builder":
            builder.begin(Track(lengthCells: 80, pieces: []), name: "TRACK 1")
            enterBuilder()
        case "soloresults":
            solo = 0
            restart(with: race.tuning)
            var bike = BikeState()
            bike.x = race.terrain.finishX - 40
            race = Race(track: round.track, tuning: race.tuning, bike: bike, rivals: 0)
            mode = .racing
            menu.hide()
            hud.isHidden = false
        case "standings":
            cup.record([1, 3, 2, 4])
            showStandings()
        case "pause":
            beginCountdown()
            pause()
        case "results":
            // Start just before the line so the results panel comes up within seconds.
            var bike = BikeState()
            bike.x = race.terrain.finishX - 40
            race = Race(track: round.track, tuning: race.tuning, bike: bike, rivals: GameScene.rivalCount)
            mode = .racing
            menu.hide()
            hud.isHidden = false
        default:
            break
        }
    }

    private var snapshotScriptDone = false

    /// In the "builder" snapshot, drags two pieces from the palette onto the track as a finger would.
    private func runBuilderScript() {
        guard snapshotMode == "builder", !snapshotScriptDone, snapshotClock > 0.4 else { return }
        snapshotScriptDone = true
        let finger = ObjectIdentifier(self)
        func world(_ p: CGPoint) -> CGPoint { CGPoint(x: cameraNode.position.x + p.x, y: cameraNode.position.y + p.y) }
        let ground = -(visibleSize.height / 2 - GameScene.groundBaseline)
        for (item, drop) in [(0, CGPoint(x: 40, y: ground + 40)), (4, CGPoint(x: 230, y: ground - 20))] {
            let from = builder.debugItemPoint(item)
            _ = builder.touchBegan(finger, at: from, world: world(from))
            builder.touchMoved(finger, at: drop, world: world(drop))
            builder.touchEnded(finger, at: drop, world: world(drop))
        }
        // Then a tap on the first piece selects it.
        let tap = CGPoint(x: 40, y: ground + 10)
        _ = builder.touchBegan(finger, at: tap, world: world(tap))
        builder.touchEnded(finger, at: tap, world: world(tap))
    }

    private func saveDueSnapshot(after elapsed: Double) {
        snapshotClock += elapsed
        runBuilderScript()
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
        if mode == .builder {
            for touch in touches {
                if let request = builder.touchBegan(ObjectIdentifier(touch), at: touch.location(in: builder),
                                                    world: touch.location(in: self)) {
                    perform(request)
                    return
                }
            }
            return
        }
        if mode == .title || mode == .soloList || mode == .library || mode == .results || mode == .standings || held {
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
        if mode == .builder {
            for touch in touches {
                builder.touchMoved(ObjectIdentifier(touch), at: touch.location(in: builder), world: touch.location(in: self))
            }
            return
        }
        input.touchesChanged(touches, in: overlay)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        liftBuilderTouches(touches)
        input.touchesEnded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        liftBuilderTouches(touches)
        input.touchesEnded(touches)
    }

    private func liftBuilderTouches(_ touches: Set<UITouch>) {
        guard mode == .builder else { return }
        for touch in touches {
            builder.touchEnded(ObjectIdentifier(touch), at: touch.location(in: builder), world: touch.location(in: self))
        }
    }

    // MARK: Drawing

    /// Moves the bike, camera and HUD to the race state. `elapsed` is simulated seconds since the last sync.
    private func syncNodes(snapCamera: Bool, elapsed: Double) {
        bikeNode.update(with: race.bike, tuning: race.tuning, elapsed: elapsed)
        for (i, node) in rivalNodes.enumerated() { node.isHidden = i + 1 >= race.bikes.count }
        for (node, bike) in zip(rivalNodes, race.bikes.dropFirst()) {
            node.update(with: bike, tuning: race.tuning, elapsed: elapsed)
        }
        hud.update(with: race, elapsed: elapsed)
        sound.update(with: race.bike, rivals: Array(race.bikes.dropFirst()), input: lastInputs.first ?? RiderInput(),
                     tuning: race.tuning,
                     engineOn: !inMenus, elapsed: elapsed)

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
            let rear = CGPoint(x: base.x - BikeNode.rearWheelOffset * cos(angle),
                               y: base.y - BikeNode.rearWheelOffset * sin(angle) + 1)
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
        builder.setScale(scale)
        builder.layout(size: visibleSize, bottomInset: insets.bottom / scale)
        menu.layout(size: visibleSize)
    }
}
