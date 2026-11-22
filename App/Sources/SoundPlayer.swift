import AVFoundation
import RaceCore

/// All game sound: an engine loop whose pitch follows the bike's speed, a boost roar layered over it,
/// the same loop quieter for each rival (louder the nearer it is, panned to its side of the player),
/// one-shot effects, and the music. Files come from `audio/compose.py`. A missing file or an audio
/// failure only makes that sound silent.
@MainActor
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case land, crash, stall, warn, pad, mud, lane, bump, count, go
    }

    // Loudness, 0...1.
    private static let musicVolume: Float = 0.3
    private static let musicVolumeAfterFinish: Float = 0.08
    private static let fanfareVolume: Float = 0.8
    private static let engineVolume: (idle: Float, gas: Float) = (0.22, 0.5)
    private static let boostVolume: Float = 0.4
    /// Engine playback rate when standing still and at boost top speed; the loop was recorded mid-rev.
    private static let engineRate: (slow: Float, fast: Float) = (0.55, 1.7)
    /// Extra rate in the air with the gas held: the wheel spins free.
    private static let airRate: Float = 0.15
    /// Rates (1/s) at which the engine and boost sounds follow the bike.
    private static let engineEasing = 8.0
    private static let boostEasing = 12.0
    /// Engine heat from which the dashboard is in its red zone, and seconds between warning beeps there.
    private static let warningHeat = 0.72
    private static let warningInterval = 0.55
    private static let voiceCount = 6
    /// Rival engines: loudness right beside the player (ticking over, and under way), the distance
    /// in metres at which one can no longer be heard and at which it sits fully to one side, and each
    /// rival's own pitch so that no two engines sound the same.
    private static let rivalVolume: (idle: Float, riding: Float) = (0.07, 0.2)
    private static let rivalEarshot = 22.0
    private static let rivalPanDistance = 10.0
    private static let rivalPitch: [Float] = [0.9, 1.07, 1.16]
    /// Below this speed (m/s) a rival's engine is only ticking over.
    private static let rivalIdleSpeed = 1.0

    private let engine = AVAudioEngine()
    private let enginePlayer = AVAudioPlayerNode()
    private let engineSpeed = AVAudioUnitVarispeed()
    private let boostPlayer = AVAudioPlayerNode()
    private let rivalPlayers = SoundPlayer.rivalPitch.map { _ in AVAudioPlayerNode() }
    private let rivalSpeeds = SoundPlayer.rivalPitch.map { _ in AVAudioUnitVarispeed() }
    private var rivalLevels = SoundPlayer.rivalPitch.map { _ in Float(0) }
    private let voices: [AVAudioPlayerNode] = (0..<SoundPlayer.voiceCount).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    private var engineLoop: AVAudioPCMBuffer?
    private var boostLoop: AVAudioPCMBuffer?
    private var effects: [Effect: AVAudioPCMBuffer] = [:]
    private var music: AVAudioPlayer?
    /// The finish stings, full-quality pieces of music: brass for a win, rock for any other place.
    private var winFanfare: AVAudioPlayer?
    private var finishFanfare: AVAudioPlayer?

    private var engineLevel: Float = 0
    private var boostLevel: Float = 0
    private var rate = SoundPlayer.engineRate.slow
    private var warningClock = 0.0
    private var silenced = false

    /// The player's sound setting, kept between launches. Off stops everything, music included.
    var isOn: Bool = UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isOn, forKey: "soundOn")
            if isOn {
                startIfNeeded()
            } else {
                music?.pause()
                stopFanfares()
                enginePlayer.volume = 0
                boostPlayer.volume = 0
                engineLevel = 0
                boostLevel = 0
                muteRivals()
            }
        }
    }

    init() {
        // Plays even with the phone's silent switch on, and alongside the player's own music.
        // Revisit once the game has its own sound on/off setting.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        engineLoop = SoundPlayer.buffer("engine")
        boostLoop = SoundPlayer.buffer("boost")
        for effect in Effect.allCases { effects[effect] = SoundPlayer.buffer(effect.rawValue) }

        let mixer = engine.mainMixerNode
        if let engineLoop {
            engine.attach(enginePlayer)
            engine.attach(engineSpeed)
            engine.connect(enginePlayer, to: engineSpeed, format: engineLoop.format)
            engine.connect(engineSpeed, to: mixer, format: engineLoop.format)
            for (player, speed) in zip(rivalPlayers, rivalSpeeds) {
                engine.attach(player)
                engine.attach(speed)
                engine.connect(player, to: speed, format: engineLoop.format)
                engine.connect(speed, to: mixer, format: engineLoop.format)
            }
        }
        if let boostLoop {
            engine.attach(boostPlayer)
            engine.connect(boostPlayer, to: mixer, format: boostLoop.format)
        }
        if let format = effects.values.first?.format {
            for voice in voices {
                engine.attach(voice)
                engine.connect(voice, to: mixer, format: format)
            }
        }
        if let url = Bundle.main.url(forResource: "theme", withExtension: "m4a") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.volume = SoundPlayer.musicVolume
        }
        winFanfare = SoundPlayer.fanfare("win")
        finishFanfare = SoundPlayer.fanfare("finish")
        startIfNeeded()
    }

    private static func fanfare(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = SoundPlayer.fanfareVolume
        player.prepareToPlay()
        return player
    }

    private static func buffer(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// Starts the audio engine and its loops; also brings them back after a phone call or another
    /// interruption stopped them.
    private func startIfNeeded() {
        guard !silenced else { return }
        if !engine.isRunning {
            guard (try? engine.start()) != nil else { return }
            enginePlayer.volume = 0
            boostPlayer.volume = 0
            engineLevel = 0
            boostLevel = 0
            muteRivals()
            if let engineLoop {
                enginePlayer.scheduleBuffer(engineLoop, at: nil, options: .loops)
                enginePlayer.play()
                for player in rivalPlayers {
                    player.scheduleBuffer(engineLoop, at: nil, options: .loops)
                    player.play()
                }
            }
            if let boostLoop {
                boostPlayer.scheduleBuffer(boostLoop, at: nil, options: .loops)
                boostPlayer.play()
            }
        }
        if isOn, music?.isPlaying == false { music?.play() }
    }

    /// What is loaded and playing, for checking a build without ears.
    var status: String {
        "engine running \(engine.isRunning), engine loop \(engineLoop != nil) playing \(enginePlayer.isPlaying) "
            + "level \(engineLevel) rate \(rate), rivals \(rivalLevels) pan \(rivalPlayers.map(\.pan)), boost loop \(boostLoop != nil), effects \(effects.count), "
            + "music loaded \(music != nil) playing \(music?.isPlaying ?? false), silenced \(silenced), "
            + "session \(AVAudioSession.sharedInstance().category.rawValue)"
    }

    /// Silences everything while the game is paused, and brings it back afterwards.
    func setSilenced(_ silent: Bool) {
        guard silent != silenced else { return }
        silenced = silent
        if silent {
            engine.pause()
            music?.pause()
            stopFanfares()
        } else {
            startIfNeeded()
        }
    }

    /// A fresh race: full music volume, no warning pending.
    func raceStarted() {
        music?.volume = SoundPlayer.musicVolume
        stopFanfares()
        warningClock = 0
    }

    private func muteRivals() {
        for player in rivalPlayers { player.volume = 0 }
        rivalLevels = rivalLevels.map { _ in 0 }
    }

    private func stopFanfares() {
        winFanfare?.stop()
        finishFanfare?.stop()
    }

    /// The player crossed the line; `won` is true for first place.
    func raceFinished(won: Bool) {
        guard !silenced, isOn else { return }
        music?.volume = SoundPlayer.musicVolumeAfterFinish
        let fanfare = won ? winFanfare : finishFanfare
        fanfare?.currentTime = 0
        fanfare?.play()
    }

    func play(_ effect: Effect, volume: Float = 1) {
        guard !silenced, isOn, engine.isRunning, let buffer = effects[effect] else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = min(max(volume, 0), 1)
        voice.scheduleBuffer(buffer, at: nil, options: [])
        voice.play()
    }

    /// Each rival's engine: quieter with distance, panned to its side of the player, pitched by its speed.
    private func updateRivals(_ rivals: [BikeState], around bike: BikeState, tuning: Tuning, on: Bool, follow: Float) {
        guard engineLoop != nil else { return }
        let rates = SoundPlayer.engineRate
        for (i, rival) in rivals.prefix(rivalPlayers.count).enumerated() {
            var down = rival.stallRemaining > 0
            if case .crashed = rival.phase { down = true }
            let away = rival.x - bike.x
            let near = Float(max(1 - abs(away) / SoundPlayer.rivalEarshot, 0))
            let riding = rival.speed > SoundPlayer.rivalIdleSpeed && !rival.finished
            let loudest = riding ? SoundPlayer.rivalVolume.riding : SoundPlayer.rivalVolume.idle
            let target = down || !on ? 0 : loudest * near * near
            rivalLevels[i] += (target - rivalLevels[i]) * follow
            let pace = Float(min(max(rival.speed / tuning.boostTopSpeed, 0), 1))
            rivalSpeeds[i].rate = (rates.slow + (rates.fast - rates.slow) * pace) * SoundPlayer.rivalPitch[i]
            rivalPlayers[i].volume = rivalLevels[i]
            rivalPlayers[i].pan = Float(min(max(away / SoundPlayer.rivalPanDistance, -1), 1))
        }
    }

    /// Continuous sound for this frame. `elapsed` is seconds since the last call; `engineOn` is false
    /// on the title screen, where only the music plays.
    func update(with bike: BikeState, rivals: [BikeState], input: RiderInput, tuning: Tuning, engineOn: Bool,
                elapsed: Double) {
        // The race is being drawn, so the game is not paused.
        setSilenced(false)
        startIfNeeded()
        var crashed = false
        if case .crashed = bike.phase { crashed = true }
        let stalled = bike.stallRemaining > 0
        let running = !stalled && !crashed && engineOn && isOn
        let gas = (input.gas || input.boost) && running && !bike.finished
        let airborne = bike.phase == .airborne

        let pace = Float(min(max(bike.speed / tuning.boostTopSpeed, 0), 1))
        let rates = SoundPlayer.engineRate
        let targetRate = rates.slow + (rates.fast - rates.slow) * pace + (airborne && gas ? SoundPlayer.airRate : 0)
        let levels = SoundPlayer.engineVolume
        let targetLevel = running ? (gas ? levels.gas : levels.idle) : 0
        let boosting = input.boost && gas && !airborne
        let targetBoost = boosting ? SoundPlayer.boostVolume : 0

        let follow = Float(1 - exp(-SoundPlayer.engineEasing * elapsed))
        rate += (targetRate - rate) * follow
        engineLevel += (targetLevel - engineLevel) * follow
        boostLevel += (targetBoost - boostLevel) * Float(1 - exp(-SoundPlayer.boostEasing * elapsed))
        engineSpeed.rate = rate
        enginePlayer.volume = engineLevel
        boostPlayer.volume = boostLevel
        updateRivals(rivals, around: bike, tuning: tuning, on: engineOn && isOn, follow: follow)

        // Beep while the engine is about to cut out.
        if bike.heat >= SoundPlayer.warningHeat, running, !bike.finished {
            warningClock -= elapsed
            if warningClock <= 0 {
                play(.warn, volume: 0.5)
                warningClock = SoundPlayer.warningInterval
            }
        } else {
            warningClock = 0
        }
    }
}
