import SwiftUI
import AVFoundation

/// All cues are generated offline from the provider's character alignment.
/// Playback time is the clock; no estimated word or character timers are used.
@MainActor @Observable
final class NarrationPlayer: NSObject {
    struct Cue: Decodable {
        let text: String
        let start: Double
        let end: Double
    }
    struct Clip: Decodable {
        let text: String
        let cues: [Cue]
        let playbackRate: Float
    }
    private(set) var available = false
    private(set) var currentWord: Int?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var clip: Clip?
    @ObservationIgnored private var contentID = ""
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var finished = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
                                              name: AVAudioSession.interruptionNotification, object: nil)
    }

    func update(id: String, text: String, playing: Bool) {
        wantsPlayback = playing
        if id != contentID {
            player?.stop()
            clock?.cancel()
            currentWord = nil
            finished = false
            contentID = id
            player = nil
            clip = nil
            available = false
            if let dataURL = Bundle.main.url(forResource: "voice-" + id, withExtension: "json"),
               let audioURL = Bundle.main.url(forResource: "voice-" + id, withExtension: "mp3"),
               let data = try? Data(contentsOf: dataURL),
               let decoded = try? JSONDecoder().decode(Clip.self, from: data), decoded.text == text,
               let audio = try? AVAudioPlayer(contentsOf: audioURL) {
                clip = decoded
                player = audio
                audio.enableRate = true
                audio.rate = decoded.playbackRate
                audio.prepareToPlay()
                available = true
            }
        }
        guard playing, !interrupted, let player else {
            player?.pause()
            clock?.cancel()
            currentWord = nil
            return
        }
        guard !player.isPlaying else { return }
        // A finished page stays finished when opening and closing pause.
        if finished { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player, player.isPlaying else { break }
                let time = player.currentTime
                self.currentWord = self.clip?.cues.firstIndex { time >= $0.start && time < $0.end }
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
            if !Task.isCancelled { self?.finished = true }
            self?.currentWord = nil
        }
    }

    func highlightedText(_ fallback: String) -> AttributedString {
        guard let clip, clip.text == fallback, let currentWord else { return AttributedString(fallback) }
        var result = AttributedString()
        for (index, cue) in clip.cues.enumerated() {
            var word = AttributedString(cue.text)
            if index == currentWord { word.foregroundColor = Color(hex: 0xFFD6A0) }
            result.append(word)
        }
        return result
    }

    @objc nonisolated private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            self?.handleInterruption(type, options: rawOptions)
        }
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType, options rawOptions: UInt) {
        interrupted = type == .began
        if interrupted {
            player?.pause()
            clock?.cancel()
            currentWord = nil
        } else {
            if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume), let clip {
                update(id: contentID, text: clip.text, playing: wantsPlayback)
            }
        }
    }
}
