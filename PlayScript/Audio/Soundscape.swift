import AVFoundation
import StoryCore
import OSLog

/// All mutable audio state and AVFoundation calls are confined to `queue`.
/// The public methods only enqueue work, so UI interactions never wait for audio.
final class Soundscape: NSObject, @unchecked Sendable {
    enum Effect: String, Sendable { case choice, turn }
    private let queue = DispatchQueue(label: "com.sh1vendra.PlayScript.audio", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.sh1vendra.PlayScript", category: "Audio")
    private var current: AVAudioPlayer?
    private var outgoing: AVAudioPlayer?
    private var effectPlayer: AVAudioPlayer?
    private var currentMood: Mood?
    private var requestedMood: Mood = .longing
    private var wantsPlayback = false
    private var interrupted = false
    private var sessionActive = false
    private var fadeGeneration = 0
    private let volume: Float = 0.38

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetAudio),
                                               name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    func set(mood: Mood, playing: Bool) {
        queue.async { [self] in update(mood: mood, playing: playing) }
    }

    func playEffect(_ effect: Effect) {
        queue.async { [self] in
            guard wantsPlayback, sessionActive, !interrupted else { return }
            effectPlayer = player(named: effect.rawValue)
            effectPlayer?.volume = effect == .choice ? 0.22 : 0.1
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
                // Ambient respects the silent switch and mixes with other audio.
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
                sessionActive = true
            } catch {
                logger.error("Audio session unavailable: \(error.localizedDescription)")
                return
            }
        }
        if mood == currentMood, let current {
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

    private func player(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
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
            effectPlayer = nil
            currentMood = nil
            sessionActive = false
            update(mood: requestedMood, playing: wantsPlayback)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
