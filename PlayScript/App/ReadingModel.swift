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
    let voice = NarrationPlayer()
    var voiceEnabled: Bool {
        didSet {
            defaults.set(voiceEnabled, forKey: Self.narrationKey)
            updateAudio()
        }
    }
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
    /// New key: an old in-page "Voice on" button read like a label but switched
    /// narration off, and that choice persisted. Everyone starts with narration on.
    private static let narrationKey = "narrationEnabled.v2"
    /// Beats where the Friar's letter itself turns the plot; the page sounds like parchment.
    private static let letterBeats: Set<String> = ["plan", "letter-lost", "road"]

    init(story: Story, defaults: UserDefaults = .standard) {
        self.story = story
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        // UI tests mute into a throwaway store, so a test run never silences a normal launch.
        let store = uiTesting ? (UserDefaults(suiteName: "PlayScriptUITesting") ?? defaults) : defaults
        self.defaults = store
        if uiTesting {
            store.removePersistentDomain(forName: "PlayScriptUITesting")
            store.set(false, forKey: "soundEnabled")
            store.set(false, forKey: Self.narrationKey)
        }
        let place = store.data(forKey: saveKey).flatMap { try? JSONDecoder().decode(SavedPlace.self, from: $0) }
        let restored = StoryRun(story: story, savedPlace: place)
        savedPlace = place == restored.savedPlace ? place : nil
        run = restored
        soundEnabled = store.object(forKey: "soundEnabled") as? Bool ?? true
        voiceEnabled = store.object(forKey: Self.narrationKey) as? Bool ?? true
        hasFinished = store.bool(forKey: "hasFinished")
    }

    var beat: StoryBeat { run.beat }
    var text: String { run.text }
    var page: [StoryLine] { run.page }
    var needsChoice: Bool { run.needsChoice }
    var canResume: Bool { savedPlace != nil }
    var contentID: String { beat.id + (run.selectedChoiceID ?? "") + "-p\(run.pageIndex)" }

    /// Narration clip IDs for the showing page, matching `Scripts/create_narration.py`.
    private var pageClips: [(id: String, text: String)] {
        let prefix = beat.id + (run.selectedChoiceID.map { "--" + $0 } ?? "")
        return zip(run.pageLineIndices, run.page).map { (id: "\(prefix)-l\($0)", text: $1.text) }
    }

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
        updateAudio()
        if soundEnabled { audio.playEffect(.choice) }
        selectionTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 500)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.45)) {
                _ = self.run.choose(choice.id)
                self.pendingChoiceID = nil
            }
            self.lastAdvance = Date()
            self.save()
            self.updateAudio()
        }
    }

    func advance() {
        guard pendingChoiceID == nil, !isPaused,
              Date().timeIntervalSince(lastAdvance) > 0.35 else { return }
        let previousBeatID = beat.id
        guard run.advance() else { return }
        lastAdvance = Date()
        save()
        updateAudio()
        if soundEnabled {
            // The letter is heard when the story reaches that beat, not on every page.
            let enteredLetterBeat = beat.id != previousBeatID && Self.letterBeats.contains(beat.id)
            audio.playEffect(enteredLetterBeat ? .letter : .turn)
        }
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
        let playing = isReading && !isPaused && isActive
        audio.set(mood: beat.mood, playing: playing && (soundEnabled || voiceEnabled),
                  ambientVolume: soundEnabled ? (needsChoice || voiceEnabled ? 0.1 : 0.38) : 0)
        voice.update(id: contentID, lines: pageClips,
                     playing: playing && voiceEnabled && pendingChoiceID == nil)
    }
}
