import XCTest

final class PlayScriptUITests: XCTestCase {
    @MainActor
    func testBookLibraryAndFutureSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Book Library"].waitForExistence(timeout: 10))
        app.buttons["searchBooks"].tap()
        XCTAssertTrue(app.alerts["A world of books, soon"].waitForExistence(timeout: 3))
        app.alerts.buttons["Back to the library"].tap()
        for _ in 0..<3 { app.swipeUp() }
        capture("library-coming-soon")
        XCTAssertTrue(app.otherElements["placeholder-Harry Potter"].exists)
        XCTAssertFalse(app.buttons["placeholder-Harry Potter"].exists)
    }

    @MainActor
    func testThreeVoiceHandoff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-cast"]
        app.launch()
        app.buttons["beginStory"].tap()
        let narrator = app.staticTexts.matching(NSPredicate(format: "identifier == 'activeSpeaker' AND label == 'NARRATOR'")).firstMatch
        XCTAssertTrue(narrator.waitForExistence(timeout: 10))
        capture("narrator-speaking")

        // The page hands off Narrator -> Juliet -> Romeo. Individual lines are short,
        // so assert against the cast the page has accumulated rather than a live label.
        let cast = app.staticTexts["speakersHeard"]
        let heardAll = NSPredicate(format: "label CONTAINS 'Narrator' AND label CONTAINS 'Juliet' AND label CONTAINS 'Romeo'")
        expectation(for: heardAll, evaluatedWith: cast)
        waitForExpectations(timeout: 60)
        capture("three-voice-handoff")
        app.buttons["pauseStory"].tap()
        XCTAssertTrue(app.buttons["resumeStory"].waitForExistence(timeout: 5))
        app.buttons["resumeStory"].tap()
        XCTAssertTrue(app.staticTexts["narrative"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testVisiblePauseAndChoiceRestoration() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["beginStory"].tap()
        app.buttons["continueStory"].tap()
        XCTAssertTrue(app.buttons["choice-listen"].waitForExistence(timeout: 5))
        app.buttons["pauseStory"].tap()
        XCTAssertTrue(app.buttons["resumeStory"].waitForExistence(timeout: 5))
        app.buttons["resumeStory"].tap()
        XCTAssertTrue(app.buttons["choice-listen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choice-answer"].exists)
        app.buttons["choice-listen"].tap()
        XCTAssertTrue(app.buttons["continueStory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["narrative"].label.contains("curtain"))
    }

    @MainActor
    func testCompleteStoryAndReplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["beginStory"].waitForExistence(timeout: 10))
        capture("01-library")
        app.buttons["beginStory"].tap()
        XCTAssertTrue(app.staticTexts["narrative"].waitForExistence(timeout: 5))
        capture("02-opening")

        var decisions = 0
        var sawWhatIf = false
        for _ in 0..<35 {
            if app.buttons["closeBook"].exists { break }
            let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'choice-'"))
            if choices.count > 0 {
                XCTAssertEqual(choices.count, 2)
                decisions += 1
                if decisions == 1 { capture("03-choice") }
                choices.element(boundBy: decisions % 2).tap()
                XCTAssertTrue(app.buttons["continueStory"].waitForExistence(timeout: 5))
            } else if app.buttons["enterWhatIf"].exists {
                sawWhatIf = true
                capture("04-what-if")
                app.buttons["enterWhatIf"].tap()
            } else {
                let next = app.buttons["continueStory"]
                XCTAssertTrue(next.waitForExistence(timeout: 5))
                if !next.isHittable { app.swipeUp() }
                next.tap()
            }
        }
        XCTAssertEqual(decisions, 3)
        XCTAssertTrue(sawWhatIf)
        XCTAssertTrue(app.staticTexts["reflectionText"].exists)
        XCTAssertTrue(app.staticTexts["personalityCharacter"].exists)
        for _ in 0..<4 {
            if app.buttons["closeBook"].isHittable { break }
            app.swipeUp()
        }
        capture("05-reflection")
        app.buttons["closeBook"].tap()
        XCTAssertTrue(app.buttons["beginStory"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["beginStory"].label, "Live the story again")
        app.buttons["beginStory"].tap()
        XCTAssertTrue(app.staticTexts["A voice in the dark"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSaveResumeAndPause() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["beginStory"].tap()
        app.buttons["continueStory"].tap()
        let choice = app.buttons["choice-listen"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertTrue(app.buttons["continueStory"].waitForExistence(timeout: 5))
        let flavor = app.staticTexts["narrative"].label
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertEqual(app.buttons["beginStory"].label, "Return to your story")
        app.buttons["beginStory"].tap()
        XCTAssertEqual(app.staticTexts["narrative"].label, flavor)
        app.staticTexts["narrative"].press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["resumeStory"].waitForExistence(timeout: 5))
        capture("06-pause")
        app.buttons["returnToLibrary"].tap()
        XCTAssertTrue(app.buttons["beginStory"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSoundPreferenceAndBackgroundResume() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let sound = app.buttons["soundToggle"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.label, "Sound off")
        sound.tap()
        XCTAssertEqual(sound.label, "Sound on")
        app.buttons["beginStory"].tap()
        XCTAssertTrue(app.staticTexts["narrative"].waitForExistence(timeout: 5))
        let text = app.staticTexts["narrative"].label
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        capture("08-return-from-background")
        XCTAssertEqual(app.staticTexts["narrative"].label, text)
        app.staticTexts["narrative"].press(forDuration: 0.8)
        XCTAssertTrue(app.switches["Original soundscape"].waitForExistence(timeout: 5))
        app.switches["Original soundscape"].tap()
        app.buttons["returnToLibrary"].tap()
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.label, "Sound off")
    }

    @MainActor
    func testAccessibilityTextRemainsScrollable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["beginStory"].waitForExistence(timeout: 5))
        app.buttons["beginStory"].tap()
        XCTAssertTrue(app.staticTexts["narrative"].waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if app.buttons["continueStory"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["continueStory"].isHittable)
        capture("07-accessibility")
        app.buttons["continueStory"].tap()
        for _ in 0..<8 {
            if app.buttons["choice-listen"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["choice-listen"].isHittable)
    }

    @MainActor
    func testLoginValidationAndSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-auth"]
        app.launch()
        let email = app.textFields["emailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        capture("09-login")

        app.buttons["primaryAuthButton"].tap()
        XCTAssertTrue(app.staticTexts["authMessage"].waitForExistence(timeout: 3))
        capture("10-login-empty-error")

        email.tap()
        email.typeText("not-an-email")
        let password = app.secureTextFields["passwordField"]
        password.tap()
        password.typeText("whatever")
        app.buttons["primaryAuthButton"].tap()
        XCTAssertTrue(app.staticTexts["authMessage"].label.contains("email"))

        replace(email, with: "juliet@verona.it")
        replace(password, with: "short")
        app.buttons["primaryAuthButton"].tap()
        XCTAssertTrue(app.staticTexts["authMessage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["authMessage"].label.contains("records"))
        capture("11-login-invalid-credentials")

        replace(password, with: "longenough")
        app.buttons["primaryAuthButton"].tap()
        XCTAssertTrue(app.buttons["beginStory"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLoginSignUpToggleAndGuest() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-auth"]
        app.launch()
        XCTAssertTrue(app.buttons["toggleAuthMode"].waitForExistence(timeout: 5))
        app.buttons["toggleAuthMode"].tap()
        XCTAssertTrue(app.secureTextFields["confirmPasswordField"].waitForExistence(timeout: 3))
        capture("12-login-signup")

        replace(app.textFields["emailField"], with: "romeo@verona.it")
        replace(app.secureTextFields["passwordField"], with: "montague")
        replace(app.secureTextFields["confirmPasswordField"], with: "capulet")
        app.buttons["primaryAuthButton"].tap()
        XCTAssertTrue(app.staticTexts["authMessage"].waitForExistence(timeout: 3))
        let mismatchMessage = app.staticTexts["authMessage"].label
        XCTAssertTrue(mismatchMessage.contains("match"), "Unexpected message: \(mismatchMessage)")

        XCTAssertTrue(app.buttons["continueAsGuest"].isHittable)
        app.buttons["continueAsGuest"].tap()
        XCTAssertTrue(app.buttons["beginStory"].waitForExistence(timeout: 5))
        capture("13-login-guest-library")
    }

    /// Clears a field by deleting what is in it. The edit menu's "Select All"
    /// is not reliably present on every iOS version.
    @MainActor private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        for _ in 0..<4 {
            // An empty field reports its placeholder as its value, so a placeholder
            // the same length as the text would otherwise look like a filled field.
            let value = (field.value as? String) ?? ""
            let existing = value == field.placeholderValue ? "" : value
            if existing.count == text.count { return }
            if !existing.isEmpty {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            }
            field.typeText(text)
        }
        XCTFail("Could not enter \(text.count) characters into \(field.identifier)")
    }

    @MainActor private func capture(_ name: String) {
        // Existence becomes true before SwiftUI's fade reaches full opacity.
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
