import AVFoundation
import StoryCore
import OSLog

/// All mutable audio state and AVFoundation calls are confined to `queue`.
/// The public methods only enqueue work, so UI interactions never wait for audio.
final class Soundscape: NSObject, @unchecked Sendable {
    enum Effect: String, Sendable { case choice, turn, letter }
    private let queue = DispatchQueue(label: "com.sh1vendra.PlayScript.audio", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.sh1vendra.PlayScript", category: "Audio")
    private var current: AVAudioPlayer?
    private var outgoing: AVAudioPlayer?
    private var effectPlayer: AVAudioPlayer?
    private var ambience: AVAudioPlayer?
    private var outgoingAmbience: AVAudioPlayer?
    private var currentAmbience: String?
    private var currentMood: Mood?
    private var requestedMood: Mood = .longing
    private var wantsPlayback = false
    private var interrupted = false
    private var sessionActive = false
    private var fadeGeneration = 0
    private var volume: Float = 0.38

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetAudio),
                                               name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    func set(mood: Mood, playing: Bool, ambientVolume: Float = 0.38) {
        queue.async { [self] in
            volume = ambientVolume
            update(mood: mood, playing: playing)
        }
    }

    func playEffect(_ effect: Effect) {
        queue.async { [self] in
            guard wantsPlayback, sessionActive, !interrupted else { return }
            let level: Float
            switch effect {
            case .choice: level = 0.22
            case .letter: level = 0.3
            case .turn: level = 0.1
            }
            effectPlayer = player(named: effect.rawValue)
            effectPlayer?.volume = level
            effectPlayer?.play()
        }
    }

    private func update(mood: Mood, playing: Bool) {
        wantsPlayback = playing
        requestedMood = mood
        guard playing, !interrupted else {
            fadeGeneration += 1
            outgoing?.stop()
            outgoing = nil
            current?.pause()
            ambience?.pause()
            outgoingAmbience?.stop()
            outgoingAmbience = nil
            effectPlayer?.stop()
            if sessionActive {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                sessionActive = false
            }
            return
        }
        if !sessionActive {
            do {
                let session = AVAudioSession.sharedInstance()
                // Must match NarrationPlayer: the story plays even with the silent switch on.
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                sessionActive = true
            } catch {
                logger.error("Audio session unavailable: \(error.localizedDescription)")
                return
            }
        }
        updateAmbience(for: mood)
        if mood == currentMood, let current {
            current.setVolume(volume, fadeDuration: 0.5)
            if !current.isPlaying {
                current.volume = 0
                current.play()
                current.setVolume(volume, fadeDuration: 0.8)
            }
            return
        }
        guard let next = player(named: mood.rawValue) else { return }
        fadeGeneration += 1
        let generation = fadeGeneration
        outgoing?.stop()
        outgoing = current
        current = next
        currentMood = mood
        next.numberOfLoops = -1
        next.volume = 0
        next.play()
        next.setVolume(volume, fadeDuration: 1.6)
        outgoing?.setVolume(0, fadeDuration: 1.6)
        queue.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.outgoing?.stop()
            self.outgoing = nil
        }
    }

    /// A quiet location loop sits under the score so each setting keeps its own room tone.
    private func updateAmbience(for mood: Mood) {
        let setting: String
        switch mood {
        case .longing, .tender: setting = "orchard"
        case .uneasy: setting = "candle"
        case .grief: setting = "tomb"
        case .dawn: setting = "road"
        }
        let ambientLevel = volume * 0.55
        if setting == currentAmbience, let ambience {
            if !ambience.isPlaying { ambience.play() }
            ambience.setVolume(ambientLevel, fadeDuration: 1.2)
            return
        }
        guard let next = player(named: setting) else {
            currentAmbience = nil
            return
        }
        outgoingAmbience?.stop()
        outgoingAmbience = ambience
        outgoingAmbience?.setVolume(0, fadeDuration: 1.2)
        let generation = fadeGeneration
        queue.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.outgoingAmbience?.stop()
            self.outgoingAmbience = nil
        }
        ambience = next
        currentAmbience = setting
        next.numberOfLoops = -1
        next.volume = 0
        next.play()
        next.setVolume(ambientLevel, fadeDuration: 2.0)
    }

    /// Generated ElevenLabs score and effects take precedence; the original
    /// synthesized WAVs remain the fallback when a clip is not bundled.
    private func player(named name: String) -> AVAudioPlayer? {
        let candidates = [("fx-" + name, "mp3"), ("score-" + name, "mp3"), (name, "wav")]
        guard let url = candidates.lazy.compactMap({
            Bundle.main.url(forResource: $0.0, withExtension: $0.1)
        }).first else {
            logger.error("Missing bundled audio: \(name)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            logger.error("Could not load audio: \(error.localizedDescription)")
            return nil
        }
    }

    @objc private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
        queue.async { [self] in
            if type == .began {
                interrupted = true
                sessionActive = false
                fadeGeneration += 1
                current?.pause()
                outgoing?.stop()
                outgoing = nil
                ambience?.pause()
                outgoingAmbience?.stop()
                outgoingAmbience = nil
                effectPlayer?.stop()
            } else {
                interrupted = false
                if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    update(mood: requestedMood, playing: wantsPlayback)
                }
            }
        }
    }

    @objc private func resetAudio() {
        queue.async { [self] in
            fadeGeneration += 1
            current = nil
            outgoing = nil
            ambience = nil
            outgoingAmbience = nil
            effectPlayer = nil
            currentMood = nil
            currentAmbience = nil
            sessionActive = false
            update(mood: requestedMood, playing: wantsPlayback)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
