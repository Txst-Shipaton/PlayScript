import SwiftUI
import StoryCore

@MainActor @Observable
final class ReadingModel {
    let story: Story
    private(set) var run: StoryRun
    var isReading = false
    var isPaused = false
    private(set) var pendingChoiceID: String?
    private(set) var savedPlace: SavedPlace?
    private(set) var hasFinished: Bool
    var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: "soundEnabled")
            updateAudio()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let audio = Soundscape()
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var lastAdvance = Date.distantPast
    private let saveKey = "playscript.savedPlace.v1"

    init(story: Story, defaults: UserDefaults = .standard) {
        self.story = story
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            defaults.removeObject(forKey: saveKey)
            defaults.removeObject(forKey: "hasFinished")
            defaults.set(false, forKey: "soundEnabled")
        }
        let place = defaults.data(forKey: saveKey).flatMap { try? JSONDecoder().decode(SavedPlace.self, from: $0) }
        let restored = StoryRun(story: story, savedPlace: place)
        savedPlace = place == restored.savedPlace ? place : nil
        run = restored
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        hasFinished = defaults.bool(forKey: "hasFinished")
    }

    var beat: StoryBeat { run.beat }
    var text: String { run.text }
    var needsChoice: Bool { run.needsChoice }
    var canResume: Bool { savedPlace != nil }
    var contentID: String { beat.id + (run.selectedChoiceID ?? "") }

    func start(over: Bool = false) {
        cancelSelection()
        run = StoryRun(story: story, savedPlace: over ? nil : savedPlace)
        isPaused = false
        isReading = true
        lastAdvance = .distantPast
        save()
        updateAudio()
    }

    func select(_ choice: StoryChoice, reduceMotion: Bool) {
        guard run.needsChoice, pendingChoiceID == nil, !isPaused else { return }
        pendingChoiceID = choice.id
        if soundEnabled { audio.playEffect(.choice) }
        selectionTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 650 : 1100)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.45)) {
                _ = self.run.choose(choice.id)
                self.pendingChoiceID = nil
            }
            self.lastAdvance = Date()
            self.save()
        }
    }

    func advance() {
        guard pendingChoiceID == nil, !isPaused,
              Date().timeIntervalSince(lastAdvance) > 0.5 else { return }
        guard run.advance() else { return }
        lastAdvance = Date()
        save()
        updateAudio()
        if soundEnabled { audio.playEffect(.turn) }
    }

    func pause() {
        guard beat.kind != .reflection else { return }
        cancelSelection()
        isPaused = true
        updateAudio()
    }

    func resume() {
        isPaused = false
        updateAudio()
    }

    func returnToLibrary() {
        cancelSelection()
        isReading = false
        isPaused = false
        updateAudio()
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active { cancelSelection() }
        updateAudio()
    }

    private func save() {
        if beat.kind == .reflection {
            hasFinished = true
            defaults.set(true, forKey: "hasFinished")
            savedPlace = nil
            defaults.removeObject(forKey: saveKey)
        } else {
            savedPlace = run.savedPlace
            if let data = try? JSONEncoder().encode(run.savedPlace) {
                defaults.set(data, forKey: saveKey)
            }
        }
    }

    private func cancelSelection() {
        selectionTask?.cancel()
        selectionTask = nil
        pendingChoiceID = nil
    }

    private func updateAudio() {
        audio.set(mood: beat.mood, playing: isReading && !isPaused && isActive && soundEnabled)
    }
}
