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
            // Each passage is now read over several pages; record each beat once.
            if visited.last != run.beat.id { visited.append(run.beat.id) }
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
        let advancedPastEnd = run.advance()
        #expect(!advancedPastEnd)
    }
}

@Test func saveRestoresBothAChoiceAndItsFlavor() throws {
    let story = try Story.bundled()
    var run = StoryRun(story: story)
    var steps = 0
    while !run.needsChoice, steps < 200 {
        #expect(run.advance())
        steps += 1
    }
    let choseInvalid = run.choose("invalid")
    #expect(!choseInvalid)
    #expect(run.needsChoice)
    run.choose(run.beat.choices[1].id)
    let savedData = try JSONEncoder().encode(run.savedPlace)
    let restored = StoryRun(story: story, savedPlace: try JSONDecoder().decode(SavedPlace.self, from: savedData))
    #expect(restored.text == run.text)
    #expect(restored.index == run.index)
    #expect(!restored.needsChoice)
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

@Test func everyPassageReadsAsAttributedLinesTwoAtATime() throws {
    let story = try Story.bundled()
    let speakers: Set<String> = ["Juliet", "Romeo"]
    for beat in story.beats {
        let lines = try #require(beat.lines, "\(beat.id) has no lines")
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { speakers.contains($0.speaker) })
        // `text` is the accessibility fallback and must not drift from the lines.
        #expect(beat.text == lines.map(\.text).joined(separator: "\n\n"))
        let pages = Pagination.pages(lines)
        #expect(pages.allSatisfy { $0.count <= Pagination.linesPerPage })
        #expect(pages.flatMap { $0 } == lines)
        for choice in beat.choices {
            let reply = try #require(choice.lines, "\(beat.id)/\(choice.id) has no lines")
            #expect(reply.allSatisfy { speakers.contains($0.speaker) })
            #expect(choice.flavor == reply.map(\.text).joined(separator: "\n\n"))
        }
    }
}

@Test func bothLoversSpeakBeforeTheStoryTurns() throws {
    let story = try Story.bundled()
    let spoken = Set((story.beats.flatMap { $0.lines ?? [] }).map(\.speaker))
    #expect(spoken == ["Juliet", "Romeo"])
    // Juliet is alone with the vial; that solitude is the point of the chamber.
    let chamber = try #require(story.beats.first { $0.id == "potion-choice" })
    #expect((chamber.lines ?? []).allSatisfy { $0.speaker == "Juliet" })
}

@Test func pagingRunsThroughEveryLineOfAPassage() throws {
    let story = try Story.bundled()
    var run = StoryRun(story: story)
    let expected = Pagination.pages(run.lines)
    #expect(expected.count > 1, "the opening passage should take more than one page")
    for (index, page) in expected.enumerated() {
        #expect(run.pageIndex == index)
        #expect(run.page == page)
        if index < expected.count - 1 {
            #expect(!run.isLastPage)
            #expect(run.advance())
            #expect(run.beat.id == story.beats[0].id, "paging must stay inside the beat")
        }
    }
    #expect(run.isLastPage)
    #expect(run.advance())
    #expect(run.beat.id == story.beats[1].id)
    #expect(run.pageIndex == 0)
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
