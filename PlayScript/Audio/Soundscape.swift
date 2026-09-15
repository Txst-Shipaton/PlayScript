import AVFoundation
import StoryCore
import OSLog

/// All sound is bundled PCM audio. No synthesis, download, or network work at runtime.
@MainActor
final class Soundscape: NSObject {
    enum Effect: String { case choice, turn }
    private let logger = Logger(subsystem: "com.sh1vendra.PlayScript", category: "Audio")
    private var current: AVAudioPlayer?
    private var outgoing: AVAudioPlayer?
    private var effectPlayer: AVAudioPlayer?
    private var currentMood: Mood?
    private var requestedMood: Mood = .longing
    private var wantsPlayback = false
    private var interrupted = false
    private var fadeTask: Task<Void, Never>?
    private let volume: Float = 0.38

    override init() {
        super.init()
        do {
            // Ambient respects the silent switch and mixes with the listener's audio.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch { logger.error("Audio session unavailable: \(error.localizedDescription)") }
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetAudio),
                                               name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    func set(mood: Mood, playing: Bool) {
        wantsPlayback = playing
        requestedMood = mood
        guard playing, !interrupted else {
            fadeTask?.cancel()
            outgoing?.stop()
            outgoing = nil
            current?.pause()
            effectPlayer?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { logger.error("Could not activate audio: \(error.localizedDescription)") }
        if mood == currentMood, let current {
            if !current.isPlaying {
                current.volume = 0
                current.play()
                current.setVolume(volume, fadeDuration: 0.8)
            }
            return
        }
        guard let next = player(named: mood.rawValue) else { return }
        fadeTask?.cancel()
        outgoing?.stop()
        outgoing = current
        current = next
        currentMood = mood
        next.numberOfLoops = -1
        next.volume = 0
        next.play()
        next.setVolume(volume, fadeDuration: 1.6)
        outgoing?.setVolume(0, fadeDuration: 1.6)
        fadeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1700)) } catch { return }
            self?.outgoing?.stop()
            self?.outgoing = nil
        }
    }

    func playEffect(_ effect: Effect) {
        guard wantsPlayback, !interrupted else { return }
        effectPlayer = player(named: effect.rawValue)
        effectPlayer?.volume = effect == .choice ? 0.22 : 0.1
        effectPlayer?.play()
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
        if type == .began {
            interrupted = true
            current?.pause()
            outgoing?.pause()
            effectPlayer?.stop()
        } else {
            interrupted = false
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                set(mood: requestedMood, playing: wantsPlayback)
            }
        }
    }

    @objc private func resetAudio() {
        fadeTask?.cancel()
        current = nil
        outgoing = nil
        currentMood = nil
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        set(mood: requestedMood, playing: wantsPlayback)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
