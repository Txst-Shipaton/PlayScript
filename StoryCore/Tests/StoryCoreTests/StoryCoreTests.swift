import Foundation
import Testing
@testable import StoryCore

@Test func allEightChoiceCombinationsFollowExactlyTheSamePlot() throws {
    let story = try Story.bundled()
    #expect(story.beats.filter { $0.kind == .choice }.count == 3)
    for combination in 0..<8 {
        var run = StoryRun(story: story)
        var visited: [String] = []
        var decision = 0
        repeat {
            visited.append(run.beat.id)
            if run.needsChoice {
                let index = run.index
                let advancedBeforeChoice = run.advance()
                #expect(!advancedBeforeChoice)
                let option = run.beat.choices[(combination >> decision) & 1]
                let chose = run.choose(option.id)
                #expect(chose)
                #expect(run.text == option.flavor)
                #expect(run.index == index)
                let choseAgain = run.choose(option.id)
                #expect(!choseAgain)
                decision += 1
            }
        } while run.advance()
        #expect(visited == story.beats.map(\.id))
        #expect(run.beat.kind == .reflection)
        #expect(run.decisions.count == 3)
        let reflection = ChoiceReflection(decisions: run.decisions)
        #expect(reflection.traits.count == 3)
        #expect(reflection.character == (combination.nonzeroBitCount <= 1 ? "Romeo" : "Juliet"))
        let advancedPastEnd = run.advance()
        #expect(!advancedPastEnd)
    }
}

@Test func saveRestoresBothAChoiceAndItsFlavor() throws {
    let story = try Story.bundled()
    var run = StoryRun(story: story)
    run.advance()
    let choseInvalid = run.choose("invalid")
    #expect(!choseInvalid)
    #expect(run.needsChoice)
    run.choose(run.beat.choices[1].id)
    let savedData = try JSONEncoder().encode(run.savedPlace)
    let restored = StoryRun(story: story, savedPlace: try JSONDecoder().decode(SavedPlace.self, from: savedData))
    #expect(restored.text == run.text)
    #expect(restored.index == run.index)
    #expect(!restored.needsChoice)
    #expect(restored.decisions == run.decisions)
}

@Test func decisionsSurviveLaterPagesAndLegacySavesStillOpen() throws {
    let story = try Story.bundled()
    var run = StoryRun(story: story)
    run.advance()
    run.choose("listen")
    run.advance()
    let saved = try JSONEncoder().encode(run.savedPlace)
    let restored = StoryRun(story: story, savedPlace: try JSONDecoder().decode(SavedPlace.self, from: saved))
    #expect(restored.decisions["window-choice"] == "listen")
    let legacy = Data(#"{"storyID":"romeo-and-juliet","beatID":"window-choice","selectedChoiceID":"answer"}"#.utf8)
    let legacyRun = StoryRun(story: story, savedPlace: try JSONDecoder().decode(SavedPlace.self, from: legacy))
    #expect(legacyRun.decisions["window-choice"] == "answer")
    #expect(legacyRun.selectedChoiceID == "answer")
    #expect(StoryRun(story: story).decisions.isEmpty)
}

@Test func obsoleteSavedPlacesRecoverSafely() throws {
    let story = try Story.bundled()
    let unknownBeat = SavedPlace(storyID: story.id, beatID: "missing", selectedChoiceID: nil)
    #expect(StoryRun(story: story, savedPlace: unknownBeat).index == 0)
    let otherStory = SavedPlace(storyID: "other", beatID: "names", selectedChoiceID: nil)
    #expect(StoryRun(story: story, savedPlace: otherStory).index == 0)
    let unknownOption = SavedPlace(storyID: story.id, beatID: "window-choice", selectedChoiceID: "missing")
    #expect(StoryRun(story: story, savedPlace: unknownOption).needsChoice)
}

@Test func alternateEndingIsExplicitAndChangesPointOfViewOnlyAfterPrompt() throws {
    let story = try Story.bundled()
    let prompt = try #require(story.beats.firstIndex { $0.kind == .whatIf })
    #expect(story.beats[..<prompt].allSatisfy { $0.pointOfView == "Juliet" })
    #expect(story.beats[(prompt + 1)...].allSatisfy { $0.pointOfView == "Romeo" })
    #expect(story.beats[(prompt + 1)...].filter { $0.kind != .reflection }.allSatisfy { $0.location.contains("imagined ending") })
}

@Test func invalidDecisionDataIsRejected() throws {
    let story = try Story.bundled()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(story)) as? [String: Any])
    var beats = try #require(object["beats"] as? [[String: Any]])
    let decision = try #require(beats.firstIndex { $0["kind"] as? String == "choice" })
    beats[decision]["choices"] = []
    object["beats"] = beats
    let invalid = try JSONDecoder().decode(Story.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: StoryError.self) { try invalid.validate() }
}
