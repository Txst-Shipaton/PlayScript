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
    /// Which line of the current page is speaking, so the view can mark it.
    private(set) var currentLine = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var clip: Clip?
    @ObservationIgnored private var queue: [(id: String, text: String)] = []
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

    /// A page is one or two lines, each its own clip in its own character's voice.
    /// They play in order, so both lovers can speak within a single page.
    func update(id: String, lines: [(id: String, text: String)], playing: Bool) {
        wantsPlayback = playing
        if id != contentID {
            player?.stop()
            clock?.cancel()
            currentWord = nil
            currentLine = 0
            finished = false
            contentID = id
            player = nil
            clip = nil
            queue = lines
            // A page is readable only if every one of its lines has a bundled clip.
            available = lines.allSatisfy { line in
                guard let dataURL = Bundle.main.url(forResource: "voice-" + line.id, withExtension: "json"),
                      Bundle.main.url(forResource: "voice-" + line.id, withExtension: "mp3") != nil,
                      let data = try? Data(contentsOf: dataURL),
                      let decoded = try? JSONDecoder().decode(Clip.self, from: data) else { return false }
                return decoded.text == line.text
            }
            if available { load(lineAt: 0) }
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
        // Playback, not ambient: a narrated story must be heard with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        startClock()
    }

    private func load(lineAt index: Int) {
        guard queue.indices.contains(index),
              let dataURL = Bundle.main.url(forResource: "voice-" + queue[index].id, withExtension: "json"),
              let audioURL = Bundle.main.url(forResource: "voice-" + queue[index].id, withExtension: "mp3"),
              let data = try? Data(contentsOf: dataURL),
              let decoded = try? JSONDecoder().decode(Clip.self, from: data),
              let audio = try? AVAudioPlayer(contentsOf: audioURL) else { return }
        clip = decoded
        player = audio
        currentLine = index
        currentWord = nil
        audio.enableRate = true
        audio.rate = decoded.playbackRate
        audio.prepareToPlay()
    }

    /// Follows playback through the page: one clip per line, in order.
    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                while !Task.isCancelled, player.isPlaying {
                    let time = player.currentTime
                    self.currentWord = self.clip?.cues.firstIndex { time >= $0.start && time < $0.end }
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                self.currentWord = nil
                // Only a line that actually played out hands over to the next one;
                // a pause leaves the page where it is.
                let reachedEnd = player.currentTime >= player.duration - 0.08
                guard self.wantsPlayback, !self.interrupted, reachedEnd else { return }
                let next = self.currentLine + 1
                guard self.queue.indices.contains(next) else {
                    self.finished = true
                    return
                }
                self.load(lineAt: next)
                self.player?.play()
            }
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
            if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume), clip != nil {
                update(id: contentID, lines: queue, playing: wantsPlayback)
            }
        }
    }
}
