import SwiftUI
import AVFoundation

/// A page is a playlist of attributed speech. Audio time drives the words and actors.
@MainActor @Observable
final class NarrationPlayer: NSObject, AVAudioPlayerDelegate {
    struct Cue: Decodable {
        let text: String
        let start: Double
        let end: Double
    }
    struct Segment: Decodable {
        let resource: String
        let speaker: String
        let text: String
        let cues: [Cue]
        let playbackRate: Float
    }
    struct Clip: Decodable {
        let text: String
        let segments: [Segment]
    }
    private(set) var available = false
    private(set) var currentWord: Int?
    private(set) var activeSpeaker: String?
    /// Every speaker heard on this page, in order. A UI test can assert the whole
    /// handoff without having to catch a one-second line as it passes.
    private(set) var speakersHeard: [String] = []
    private(set) var audioLevel: Double = 0
    @ObservationIgnored private var players: [AVAudioPlayer] = []
    @ObservationIgnored private var clip: Clip?
    @ObservationIgnored private var segmentIndex = 0
    @ObservationIgnored private var contentID = ""
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var finished = false

    private var player: AVAudioPlayer? { players.indices.contains(segmentIndex) ? players[segmentIndex] : nil }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
                                              name: AVAudioSession.interruptionNotification, object: nil)
    }

    func update(id: String, text: String, playing: Bool) {
        wantsPlayback = playing
        if id != contentID {
            players.forEach { $0.stop() }
            clock?.cancel()
            clearHighlight()
            finished = false
            contentID = id
            players = []
            clip = nil
            available = false
            segmentIndex = 0
            speakersHeard = []
            if let dataURL = Bundle.main.url(forResource: "cast-" + id, withExtension: "json"),
               let data = try? Data(contentsOf: dataURL),
               let decoded = try? JSONDecoder().decode(Clip.self, from: data),
               decoded.text == text, !decoded.segments.isEmpty,
               decoded.segments.map(\.text).joined() == text {
                let loaded = decoded.segments.compactMap { segment -> AVAudioPlayer? in
                    guard let url = Bundle.main.url(forResource: segment.resource, withExtension: "mp3"),
                          let audio = try? AVAudioPlayer(contentsOf: url) else { return nil }
                    audio.enableRate = true
                    audio.rate = segment.playbackRate
                    audio.isMeteringEnabled = true
                    audio.delegate = self
                    audio.prepareToPlay()
                    return audio
                }
                if loaded.count == decoded.segments.count {
                    clip = decoded
                    players = loaded
                    available = true
                }
            }
        }
        guard playing, !interrupted else {
            player?.pause()
            clock?.cancel()
            clearHighlight()
            return
        }
        playCurrentSegment()
    }

    private func clearHighlight() {
        currentWord = nil
        activeSpeaker = nil
        audioLevel = 0
    }

    private func playCurrentSegment() {
        guard !finished, wantsPlayback, !interrupted, let player,
              let segment = clip?.segments[segmentIndex], !player.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard player.play() else { clearHighlight(); return }
        activeSpeaker = segment.speaker
        if speakersHeard.last != segment.speaker { speakersHeard.append(segment.speaker) }
        let offset = clip?.segments.prefix(segmentIndex).reduce(0) { $0 + $1.cues.count } ?? 0
        clock?.cancel()
        clock = Task { [weak self, weak player] in
            while !Task.isCancelled {
                guard let self, let player, player.isPlaying else { return }
                self.currentWord = segment.cues.firstIndex { player.currentTime >= $0.start && player.currentTime < $0.end }.map { $0 + offset }
                player.updateMeters()
                self.audioLevel = min(1, max(0, pow(10, Double(player.averagePower(forChannel: 0)) / 28)))
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.clock?.cancel()
            self.clearHighlight()
            if flag && self.segmentIndex + 1 < self.players.count {
                self.segmentIndex += 1
                self.playCurrentSegment()
            } else {
                self.finished = true
            }
        }
    }

    func highlightedText(_ fallback: String) -> AttributedString {
        guard let clip, clip.text == fallback, let currentWord else { return AttributedString(fallback) }
        var result = AttributedString()
        for (index, cue) in clip.segments.flatMap(\.cues).enumerated() {
            var word = AttributedString(cue.text)
            if index == currentWord { word.foregroundColor = Color(hex: 0xFFD6A0) }
            result.append(word)
        }
        return result
    }

    @objc nonisolated private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.interrupted = type == .began
            if self.interrupted {
                self.player?.pause()
                self.clock?.cancel()
                self.clearHighlight()
            } else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                self.playCurrentSegment()
            }
        }
    }
}
