import XCTest

final class PlayScriptUITests: XCTestCase {
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

        email.doubleTap()
        app.menuItems["Select All"].firstMatch.tap()
        email.typeText("juliet@verona.it")
        password.doubleTap()
        app.menuItems["Select All"].firstMatch.tap()
        password.typeText("short")
        app.buttons["primaryAuthButton"].tap()
        XCTAssertTrue(app.staticTexts["authMessage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["authMessage"].label.contains("records"))
        capture("11-login-invalid-credentials")

        password.doubleTap()
        app.menuItems["Select All"].firstMatch.tap()
        password.typeText("longenough")
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

        app.textFields["emailField"].tap()
        app.textFields["emailField"].typeText("romeo@verona.it")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("montague")
        app.secureTextFields["confirmPasswordField"].tap()
        app.secureTextFields["confirmPasswordField"].typeText("capulet")
        app.buttons["primaryAuthButton"].tap()
        XCTAssertTrue(app.staticTexts["authMessage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["authMessage"].label.contains("match"))

        XCTAssertTrue(app.buttons["continueAsGuest"].isHittable)
        app.buttons["continueAsGuest"].tap()
        XCTAssertTrue(app.buttons["beginStory"].waitForExistence(timeout: 5))
        capture("13-login-guest-library")
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
