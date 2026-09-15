import Foundation

public enum Mood: String, Codable, CaseIterable, Sendable {
    case longing, tender, uneasy, grief, dawn
}

public enum BeatKind: String, Codable, Sendable {
    case narration, choice, whatIf, reflection
}

public struct StoryChoice: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let flavor: String
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
    public let text: String
    public let choices: [StoryChoice]
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
        for beat in beats {
            guard !beat.id.isEmpty, !beat.text.isEmpty else {
                throw StoryError.invalidContent("Every beat needs an ID and text.")
            }
            if beat.kind == .choice {
                guard beat.choices.count == 2,
                      Set(beat.choices.map(\.id)).count == 2,
                      beat.choices.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.flavor.isEmpty }) else {
                    throw StoryError.invalidContent("A decision must have exactly two distinct, complete choices.")
                }
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
    public let decisions: [String: String]?

    public init(storyID: String, beatID: String, selectedChoiceID: String?, decisions: [String: String]? = nil) {
        self.storyID = storyID
        self.beatID = beatID
        self.selectedChoiceID = selectedChoiceID
        self.decisions = decisions
    }
}

/// Choices deliberately have no destinations. There is only one next beat.
public struct StoryRun: Sendable {
    public let story: Story
    public private(set) var index: Int
    public private(set) var selectedChoiceID: String?
    public private(set) var decisions: [String: String] = [:]

    public init(story: Story, savedPlace: SavedPlace? = nil) {
        self.story = story
        if let place = savedPlace, place.storyID == story.id,
           let restoredIndex = story.beats.firstIndex(where: { $0.id == place.beatID }) {
            index = restoredIndex
            selectedChoiceID = story.beats[restoredIndex].choices.first { $0.id == place.selectedChoiceID }?.id
            decisions = (place.decisions ?? [:]).filter { beatID, choiceID in
                story.beats.prefix(restoredIndex + 1).contains { $0.id == beatID && $0.choices.contains { $0.id == choiceID } }
            }
            if let selectedChoiceID { decisions[place.beatID] = selectedChoiceID }
        } else {
            index = 0
            selectedChoiceID = nil
        }
    }

    public var beat: StoryBeat { story.beats[index] }
    public var selectedChoice: StoryChoice? { beat.choices.first { $0.id == selectedChoiceID } }
    public var text: String { selectedChoice?.flavor ?? beat.text }
    public var needsChoice: Bool { beat.kind == .choice && selectedChoice == nil }
    public var savedPlace: SavedPlace {
        SavedPlace(storyID: story.id, beatID: beat.id, selectedChoiceID: selectedChoiceID, decisions: decisions)
    }

    @discardableResult
    public mutating func choose(_ id: String) -> Bool {
        guard needsChoice, beat.choices.contains(where: { $0.id == id }) else { return false }
        selectedChoiceID = id
        decisions[beat.id] = id
        return true
    }

    @discardableResult
    public mutating func advance() -> Bool {
        guard !needsChoice, index + 1 < story.beats.count else { return false }
        index += 1
        selectedChoiceID = nil
        return true
    }
}
