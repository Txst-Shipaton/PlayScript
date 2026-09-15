import Foundation

public enum Mood: String, Codable, CaseIterable, Sendable {
    case longing, tender, uneasy, grief, dawn
}

public enum BeatKind: String, Codable, Sendable {
    case narration, choice, whatIf, reflection
}

/// One spoken or thought line, attributed to whoever it belongs to.
/// The speaker drives both the on-screen attribution and the narration voice.
public struct StoryLine: Codable, Equatable, Sendable {
    public let speaker: String
    public let text: String
    /// `"beatID:choiceID"`. The line is heard only on paths where that choice was
    /// made, which is how an earlier decision echoes later in the story.
    public let when: String?

    public init(speaker: String, text: String, when: String? = nil) {
        self.speaker = speaker
        self.text = text
        self.when = when
    }
}

public struct StoryChoice: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let flavor: String
    /// When present, the reply plays as attributed lines rather than one block.
    public let lines: [StoryLine]?
}

public struct StoryBeat: Codable, Identifiable, Sendable {
    public let id: String
    public let chapter: String
    public let title: String
    public let location: String
    public let pointOfView: String
    public let mood: Mood
    /// Optional asset catalog name. Artwork is intentionally deferred for this build.
    public let artwork: String?
    public let kind: BeatKind
    /// Every written line joined, for accessibility and saved-place compatibility.
    public let text: String
    public let lines: [StoryLine]?
    public let choices: [StoryChoice]
}

/// Content is read two lines at a time, so the screen never fills with prose.
public enum Pagination {
    public static let linesPerPage = 2

    public static func pages(_ lines: [StoryLine]) -> [[StoryLine]] {
        stride(from: 0, to: lines.count, by: linesPerPage).map {
            Array(lines[$0..<min($0 + linesPerPage, lines.count)])
        }
    }
}

public struct Story: Codable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let author: String
    public let duration: String
    public let beats: [StoryBeat]

    public static func bundled() throws -> Story {
        guard let url = Bundle.module.url(forResource: "romeo-and-juliet", withExtension: "json") else {
            throw StoryError.missingResource
        }
        let story = try JSONDecoder().decode(Story.self, from: Data(contentsOf: url))
        try story.validate()
        return story
    }

    public func validate() throws {
        guard !beats.isEmpty, Set(beats.map(\.id)).count == beats.count else {
            throw StoryError.invalidContent("A story needs unique, nonempty beats.")
        }
        var decisionsSoFar: [String: Set<String>] = [:]
        for beat in beats {
            guard !beat.id.isEmpty, !beat.text.isEmpty else {
                throw StoryError.invalidContent("Every beat needs an ID and text.")
            }
            let passages = [beat.lines ?? []] + beat.choices.map { $0.lines ?? [] }
            for passage in passages {
                guard passage.allSatisfy({ !$0.speaker.isEmpty && !$0.text.isEmpty }) else {
                    throw StoryError.invalidContent("Every line needs a speaker and text.")
                }
                // Something must be heard on every path, whatever was chosen before.
                if !passage.isEmpty, !passage.contains(where: { $0.when == nil }) {
                    throw StoryError.invalidContent("\(beat.id) has no line heard on every path.")
                }
                for condition in passage.compactMap(\.when) {
                    let parts = condition.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2, decisionsSoFar[parts[0]]?.contains(parts[1]) == true else {
                        throw StoryError.invalidContent("\(beat.id): '\(condition)' must name an earlier choice.")
                    }
                }
            }
            if let lines = beat.lines, lines.isEmpty {
                throw StoryError.invalidContent("A beat with lines needs at least one.")
            }
            if beat.kind == .choice {
                guard beat.choices.count == 2,
                      Set(beat.choices.map(\.id)).count == 2,
                      beat.choices.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.flavor.isEmpty }) else {
                    throw StoryError.invalidContent("A decision must have exactly two distinct, complete choices.")
                }
                decisionsSoFar[beat.id] = Set(beat.choices.map(\.id))
            } else if !beat.choices.isEmpty {
                throw StoryError.invalidContent("Only decision beats may contain choices.")
            }
        }
        guard beats.last?.kind == .reflection else {
            throw StoryError.invalidContent("A story must end with a reflection.")
        }
    }
}

public enum StoryError: Error {
    case missingResource
    case invalidContent(String)
}

/// Stable IDs keep a saved place valid when text or beat ordering is edited.
public struct SavedPlace: Codable, Equatable, Sendable {
    public let storyID: String
    public let beatID: String
    public let selectedChoiceID: String?
    /// Every decision made so far, so later echoes survive a relaunch.
    public let choices: [String: String]?

    public init(storyID: String, beatID: String, selectedChoiceID: String?,
                choices: [String: String]? = nil) {
        self.storyID = storyID
        self.beatID = beatID
        self.selectedChoiceID = selectedChoiceID
        self.choices = choices
    }
}

/// The plot has one next beat; choices change what is said along the way.
public struct StoryRun: Sendable {
    public let story: Story
    public private(set) var index: Int
    public private(set) var selectedChoiceID: String?
    /// Which two-line page of the current passage is showing.
    public private(set) var pageIndex: Int
    /// Decisions made on this path, beat ID to choice ID.
    public private(set) var history: [String: String]

    public init(story: Story, savedPlace: SavedPlace? = nil) {
        self.story = story
        pageIndex = 0
        if let place = savedPlace, place.storyID == story.id,
           let restoredIndex = story.beats.firstIndex(where: { $0.id == place.beatID }) {
            index = restoredIndex
            let current = story.beats[restoredIndex]
            let chosen = current.choices.first { $0.id == place.selectedChoiceID }?.id
            selectedChoiceID = chosen
            var restored: [String: String] = [:]
            // Only decisions that still exist, made before this point, carry over.
            for (beatID, choiceID) in place.choices ?? [:] {
                guard let at = story.beats.firstIndex(where: { $0.id == beatID }), at < restoredIndex,
                      story.beats[at].choices.contains(where: { $0.id == choiceID }) else { continue }
                restored[beatID] = choiceID
            }
            restored[current.id] = chosen
            history = restored
        } else {
            index = 0
            selectedChoiceID = nil
            history = [:]
        }
    }

    public var beat: StoryBeat { story.beats[index] }
    public var selectedChoice: StoryChoice? { beat.choices.first { $0.id == selectedChoiceID } }
    public var text: String { selectedChoice?.flavor ?? beat.text }

    /// Every written line of what is showing, before earlier choices are applied.
    private var writtenLines: [StoryLine] {
        if let choice = selectedChoice {
            return choice.lines ?? [StoryLine(speaker: beat.pointOfView, text: choice.flavor)]
        }
        return beat.lines ?? [StoryLine(speaker: beat.pointOfView, text: beat.text)]
    }

    private func isHeard(_ line: StoryLine) -> Bool {
        guard let condition = line.when else { return true }
        let parts = condition.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 && history[parts[0]] == parts[1]
    }

    /// Written positions of the lines heard on this path. Narration clips are named
    /// by written position, so a clip keeps its name whichever path reaches it.
    public var lineIndices: [Int] { writtenLines.indices.filter { isHeard(writtenLines[$0]) } }
    public var lines: [StoryLine] { lineIndices.map { writtenLines[$0] } }
    public var pages: [[StoryLine]] { Pagination.pages(lines) }
    public var page: [StoryLine] { pages.indices.contains(pageIndex) ? pages[pageIndex] : [] }
    public var pageLineIndices: [Int] {
        let heard = lineIndices
        let start = pageIndex * Pagination.linesPerPage
        guard start < heard.count else { return [] }
        return Array(heard[start..<min(start + Pagination.linesPerPage, heard.count)])
    }
    public var isLastPage: Bool { pageIndex >= pages.count - 1 }

    /// The decision waits until its passage has been read to the end.
    public var needsChoice: Bool { beat.kind == .choice && selectedChoice == nil && isLastPage }
    public var savedPlace: SavedPlace {
        SavedPlace(storyID: story.id, beatID: beat.id, selectedChoiceID: selectedChoiceID,
                   choices: history.isEmpty ? nil : history)
    }

    @discardableResult
    public mutating func choose(_ id: String) -> Bool {
        guard needsChoice, beat.choices.contains(where: { $0.id == id }) else { return false }
        selectedChoiceID = id
        history[beat.id] = id
        pageIndex = 0
        return true
    }

    @discardableResult
    public mutating func advance() -> Bool {
        guard !needsChoice else { return false }
        if !isLastPage {
            pageIndex += 1
            return true
        }
        guard index + 1 < story.beats.count else { return false }
        index += 1
        selectedChoiceID = nil
        pageIndex = 0
        return true
    }
}
