import XCTest
import UIKit

/// Checks the secondary screens at the largest supported reading size. Run the
/// same tests under the simulator's real light and dark appearances. Fixtures
/// exercise native layout and saved words, not speech or rewrite model quality.
@MainActor
final class DesignLanguageUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testLargestTextKeepsNavigationAndModeEditingComfortable() {
        let app = launch()
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        for identifier in ["recordButton", "historyButton", "settingsButton", "modeButton"] {
            assertComfortableTarget(app.buttons[identifier], in: app)
        }
        capture("Design-AX-Home", app: app)

        app.buttons["historyButton"].tap()
        let history = app.navigationBars["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["emptyHistory"].firstMatch.exists)
        assertNativeAction(history.buttons["Done"], in: app)
        capture("Design-AX-Empty-History", app: app)
        history.buttons["Done"].tap()

        app.buttons["modeButton"].tap()
        XCTAssertTrue(app.navigationBars["Modes"].waitForExistence(timeout: 5))
        let cleanEditor = app.buttons["edit-mode-clean"]
        reveal(cleanEditor, in: app, container: "writingModesScrollView")
        assertComfortableTarget(cleanEditor, in: app)
        capture("Design-AX-Modes", app: app)
        cleanEditor.tap()
        XCTAssertTrue(app.navigationBars["Clean prompt"].waitForExistence(timeout: 5))
        capture("Design-AX-Mode-Editor-Before-Reveal", app: app)
        let promptEditor = app.textViews["rewritePromptEditor"]
        reveal(promptEditor, in: app, container: "writingStyleEditorForm", requireCompleteFrame: false)
        XCTAssertTrue(promptEditor.waitForExistence(timeout: 5))
        let savedPrompt = promptEditor.value as? String
        XCTAssertNotNil(savedPrompt)
        for identifier in ["saveModeButton", "cancelModeButton"] {
            assertNativeAction(app.buttons[identifier], in: app)
        }
        capture("Design-AX-Mode-Editor", app: app)
        promptEditor.tap()
        promptEditor.typeText(" Keep it brief.")
        XCTAssertTrue((promptEditor.value as? String)?.contains("Keep it brief.") == true)
        XCTAssertNotEqual(promptEditor.value as? String, savedPrompt)
        for identifier in ["saveModeButton", "cancelModeButton"] {
            assertNativeAction(app.buttons[identifier], in: app)
        }
        capture("Design-AX-Mode-Editor-Draft-With-Keyboard", app: app)
        app.buttons["cancelModeButton"].tap()
        app.navigationBars["Modes"].buttons["Done"].tap()

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let speech = app.descendants(matching: .any)["speechProviderPicker"].firstMatch
        reveal(speech, in: app, container: "settingsForm")
        assertComfortableTarget(speech, in: app)
        capture("Design-AX-Settings", app: app)
        speech.tap()
        let parakeet = app.buttons["Parakeet · local"].firstMatch
        XCTAssertTrue(parakeet.waitForExistence(timeout: 5))
        parakeet.tap()
        let localSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Parakeet · local"), object: speech)
        XCTAssertEqual(XCTWaiter.wait(for: [localSelected], timeout: 5), .completed)
        reveal(speech, in: app, container: "settingsForm")
        assertComfortableTarget(speech, in: app)
        capture("Design-AX-Parakeet-Selection", app: app)
        speech.tap()
        let apple = app.buttons["Apple Speech"].firstMatch
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        apple.tap()
        let appleSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Apple Speech"), object: speech)
        XCTAssertEqual(XCTWaiter.wait(for: [appleSelected], timeout: 5), .completed)

        let language = app.descendants(matching: .any)["languagePicker"].firstMatch
        reveal(language, in: app, container: "settingsForm")
        assertComfortableTarget(language, in: app)
        capture("Design-AX-Language", app: app)
        language.tap()
        // English (UK) is a defined SpeechLanguage choice. The simulator may
        // append availability status; selecting it does not download assets.
        let english = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "English (UK)")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        let selectedLanguage = english.label
        english.tap()
        let languageSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", selectedLanguage), object: language)
        XCTAssertEqual(XCTWaiter.wait(for: [languageSelected], timeout: 5), .completed)
        assertComfortableTarget(language, in: app)
        capture("Design-AX-Language-Selected", app: app)

        // Reopening Settings must preserve both selections and their full
        // accessible values after returning through the Home screen.
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(speech.value as? String, "Apple Speech")
        reveal(language, in: app, container: "settingsForm")
        XCTAssertEqual(language.value as? String, selectedLanguage)
        assertComfortableTarget(language, in: app)
        let writingModes = app.buttons["writingModesSettingsButton"]
        reveal(writingModes, in: app, container: "settingsForm")
        assertComfortableTarget(writingModes, in: app)
        writingModes.tap()
        XCTAssertTrue(app.navigationBars["Writing modes"].waitForExistence(timeout: 5))
        reveal(cleanEditor, in: app, container: "writingModesSettingsForm")
        assertComfortableTarget(cleanEditor, in: app)
        capture("Design-AX-Settings-Modes", app: app)
        cleanEditor.tap()
        XCTAssertTrue(app.navigationBars["Clean prompt"].waitForExistence(timeout: 5))
        capture("Design-AX-Settings-Mode-Editor-Before-Reveal", app: app)
        reveal(promptEditor, in: app, container: "writingStyleEditorForm", requireCompleteFrame: false)
        XCTAssertTrue(promptEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(promptEditor.value as? String, savedPrompt,
                       "Cancelling the Home editor must preserve the saved prompt reached through Settings.")
        capture("Design-AX-Settings-Mode-Editor-Revealed", app: app)
        XCTAssertTrue(app.buttons["saveModeButton"].isEnabled,
                      "A saved prompt must remain usable when reached through Settings at large text.")
    }

    func testLargestTextKeepsSavedOriginalAndRewriteReachable() {
        let app = launch(previewResult: true)
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let savedText = result.label
        // The preview populates only the current result. Save through the real
        // editor before asking History to display a persisted dictation.
        let edit = app.buttons["editButton"]
        reveal(edit, in: app, container: "transcriptScrollView")
        edit.tap()
        XCTAssertTrue(app.textViews["editText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveEditButton"].isEnabled)
        app.buttons["saveEditButton"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        // The Home result remains in the hierarchy underneath the sheet, so
        // resolve the saved writing inside History rather than a global label.
        let historyList = app.descendants(matching: .any)["historyList"].firstMatch
        let saved = historyList.staticTexts.matching(NSPredicate(format: "label == %@", savedText)).firstMatch
        capture("Design-AX-History-Before-Reveal", app: app)
        reveal(saved, in: app, container: "historyList", requireCompleteFrame: false)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        capture("Design-AX-History-Revealed", app: app)
        saved.tap()
        let detail = app.staticTexts["historyDetailText"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.label, savedText)
        capture("Design-AX-Saved-Writing", app: app)

        let original = app.buttons["historyOriginalButton"]
        reveal(original, in: app, container: "historyDetailScrollView")
        assertComfortableTarget(original, in: app)
        original.tap()
        XCTAssertTrue(detail.label.hasPrefix("um let's keep it simple"))
        let originalText = detail.label
        let rewrite = app.buttons["historyRewriteButton"]
        reveal(rewrite, in: app, container: "historyDetailScrollView")
        assertComfortableTarget(rewrite, in: app)
        capture("Design-AX-Saved-Actions", app: app)
        rewrite.tap()
        let preserveOriginal = app.buttons["history-rewrite-transcript"]
        XCTAssertTrue(preserveOriginal.waitForExistence(timeout: 5))
        preserveOriginal.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, originalText,
                       "The saved original must survive navigating and rewriting at the largest text size.")
        assertComfortableTarget(app.buttons["recordButton"], in: app)
    }

    private func launch(previewResult: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        if previewResult { app.launchArguments.append("--preview-result") }
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()
        return app
    }

    private func assertComfortableTarget(_ element: XCUIElement, in app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, "Narrow target: \(element.identifier)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, "Short target: \(element.identifier)", file: file, line: line)
        assertNativeAction(element, in: app, file: file, line: line)
    }

    private func assertNativeAction(_ element: XCUIElement, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        // Native navigation buttons expose a 36pt visual accessibility frame
        // on iOS 27; that frame does not measure their system-managed hit area.
        // Require containment and real interaction, reserving geometry minimums
        // for the custom controls whose hit areas the app defines.
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame),
                      "Clipped target: \(element.identifier), \(element.frame)", file: file, line: line)
        XCTAssertTrue(element.isEnabled, file: file, line: line)
        XCTAssertTrue(element.isHittable, "Unreachable target: \(element.identifier)", file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, container identifier: String,
                        requireCompleteFrame: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        let scroll = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<30 {
            guard app.state == .runningForeground else {
                XCTFail("Sayso left the foreground while revealing \(element.identifier)", file: file, line: line)
                return
            }
            let viewport = scroll.frame.intersection(window.frame).insetBy(dx: 2, dy: 4)
            if element.exists && element.isHittable && (!requireCompleteFrame || viewport.contains(element.frame)) { return }
            let offset = element.exists ? element.frame.midY - viewport.midY : viewport.height
            // Native sheet scroll frames extend behind the home indicator.
            // Keep gestures in the central reading area, away from system edges.
            let distance = min(viewport.height * 0.4, max(20, abs(offset) * 0.5))
            let startY = viewport.minY + viewport.height * (offset > 0 ? 0.72 : 0.28)
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let x = viewport.minX + viewport.width * 0.82 - scroll.frame.minX
            let start = origin.withOffset(CGVector(dx: x,
                                                   dy: startY - scroll.frame.minY))
            let end = origin.withOffset(CGVector(dx: x,
                                                 dy: startY - scroll.frame.minY + (offset > 0 ? -distance : distance)))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Could not reveal \(element.identifier): \(element.frame)", file: file, line: line)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
