import XCTest
import UIKit

/// Covers the recording workspace and its new recent-thought shortcut through
/// real navigation, editing, and persistence. Run on the smallest supported
/// phone in both system appearances; screenshot names describe layout only.
/// Scripted speech exercises the controller, not microphone/model quality.
@MainActor
final class ReimaginedAppUITests: XCTestCase {
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

    func testPortraitRecordingToRecentThoughtPreservesEditsAndOriginal() throws {
        try exerciseJourney(layout: "Portrait")
    }

    func testLandscapeRecordingToRecentThoughtKeepsControlsReachable() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        try exerciseJourney(layout: "Landscape")
    }

    func testLargestTextRecordingToRecentThoughtKeepsControlsReachable() throws {
        try exerciseJourney(layout: "Accessibility-XXXL", largestText: true)
    }

    private func exerciseJourney(layout: String, largestText: Bool = false) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--scripted-speech"]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()

        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        for identifier in ["recordButton", "historyButton", "settingsButton", "modeButton"] {
            let control = app.buttons[identifier]
            reveal(control, in: app, container: "transcriptScrollView")
            assertCustomControl(control, in: app)
        }
        XCTAssertFalse(app.buttons["recentThoughtButton"].exists,
                       "A fresh workspace must not invent a saved thought.")
        capture("\(layout)-01-Empty-Workspace", app: app)

        let mode = app.buttons["modeButton"]
        reveal(mode, in: app, container: "transcriptScrollView")
        mode.tap()
        let clean = app.buttons["mode-clean"]
        XCTAssertTrue(clean.waitForExistence(timeout: 5))
        reveal(clean, in: app, container: "writingModesScrollView")
        assertCustomControl(clean, in: app)
        capture("\(layout)-02-Choose-Mode", app: app)
        clean.tap()
        waitForLabel(mode, containing: "Clean")
        assertCustomControl(record, in: app)

        record.tap()
        waitForLabel(record, equalTo: "Stop recording")
        XCTAssertFalse(app.buttons["historyButton"].isEnabled,
                       "Recording must prevent opening a conflicting saved-work flow.")
        let live = app.staticTexts["liveTranscript"]
        let completedThought = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label ENDSWITH %@", "next project."), object: live)
        XCTAssertEqual(XCTWaiter.wait(for: [completedThought], timeout: 10), .completed)
        let original = live.label
        XCTAssertFalse(original.isEmpty)
        assertCustomControl(record, in: app)
        capture("\(layout)-03-Recording", app: app)

        record.tap()
        waitForLabel(record, equalTo: "Start recording", timeout: 10)
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        if largestText {
            XCTAssertTrue(result.isHittable,
                          "The initial result viewport must show the writing at the largest text size.")
        }
        XCTAssertEqual(result.label, original)
        XCTAssertTrue(app.buttons["historyButton"].isEnabled)
        capture("\(layout)-04-Result", app: app)

        let copy = app.buttons["copyButton"]
        reveal(copy, in: app, container: "transcriptScrollView")
        assertCustomControl(copy, in: app)
        let copyFrame = copy.frame
        copy.tap()
        waitForLabel(copy, containing: "Copied")
        XCTAssertEqual(copy.frame.width, copyFrame.width, accuracy: 1,
                       "Copy feedback must preserve the action's footprint.")
        XCTAssertEqual(result.label, original)
        capture("\(layout)-05-Copied", app: app)

        let edit = app.buttons["editButton"]
        reveal(edit, in: app, container: "transcriptScrollView")
        assertCustomControl(edit, in: app)
        edit.tap()
        let editor = app.textViews["editText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, original)
        let save = app.buttons["saveEditButton"]
        assertNativeControl(save, in: app)
        editor.tap()
        editor.typeText("\nKeep this thought for Monday.")
        let edited = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(edited.contains("Keep this thought for Monday."))
        XCTAssertNotEqual(edited, original)
        assertNativeControl(save, in: app)
        capture("\(layout)-06-Edit-With-Keyboard", app: app)
        save.tap()
        waitForLabel(result, equalTo: edited)

        // Once the saved text differs, the original is a distinct reading
        // state. Copy feedback and the editor must follow that distinction.
        reveal(copy, in: app, container: "transcriptScrollView")
        copy.tap()
        waitForLabel(copy, containing: "Copied")
        let homeOriginal = app.buttons["originalButton"]
        reveal(homeOriginal, in: app, container: "transcriptScrollView")
        assertCustomControl(homeOriginal, in: app)
        homeOriginal.tap()
        waitForLabel(result, equalTo: original)
        waitForLabel(copy, equalTo: "Copy")
        capture("\(layout)-06b-Original-Copy-Ready", app: app)

        reveal(edit, in: app, container: "transcriptScrollView")
        edit.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, edited,
                       "Editing from Original must load the saved writing while preserving the transcript.")
        editor.tap()
        editor.typeText(" This draft will be cancelled.")
        XCTAssertTrue((editor.value as? String)?.contains("This draft will be cancelled.") == true)
        let cancel = app.navigationBars["Edit text"].buttons["Cancel"]
        assertNativeControl(cancel, in: app)
        cancel.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        waitForLabel(result, equalTo: original)
        waitForLabel(homeOriginal, equalTo: "Show refined")
        capture("\(layout)-06c-Cancel-Preserves-Original", app: app)

        reveal(edit, in: app, container: "transcriptScrollView")
        edit.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, edited,
                       "A cancelled draft must not replace the saved edit.")
        // Saving the loaded text also checks that Save works before the first
        // keystroke and leaves Original to reveal the text just saved.
        assertNativeControl(save, in: app)
        save.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        waitForLabel(result, equalTo: edited)
        waitForLabel(homeOriginal, equalTo: "Show original")
        capture("\(layout)-06d-Save-Reveals-Saved-Writing", app: app)

        // No preview result is injected. Relaunch must rebuild Home's recent
        // card from the file written by this journey, including its edit.
        app.terminate()
        app.launch()
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        waitForLabel(mode, containing: "Clean")
        let recent = app.buttons["recentThoughtButton"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        reveal(recent, in: app, container: "transcriptScrollView")
        assertCustomControl(recent, in: app)
        capture("\(layout)-07-Saved-Thought-On-Home", app: app)
        recent.tap()

        let detail = app.staticTexts["historyDetailText"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        if largestText {
            XCTAssertTrue(detail.isHittable,
                          "The recent thought must show its writing immediately at the largest text size.")
        }
        XCTAssertEqual(detail.label, edited,
                       "The recent shortcut must open the saved edit, not a stale result.")
        capture("\(layout)-08-Recent-Thought-Detail", app: app)

        let recentDone = app.navigationBars.buttons["Done"].firstMatch
        assertNativeControl(recentDone, in: app)
        recentDone.tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5))
        assertCustomControl(record, in: app)
        let viewAll = app.buttons["viewAllHistoryButton"]
        reveal(viewAll, in: app, container: "transcriptScrollView")
        assertCustomControl(viewAll, in: app)
        viewAll.tap()
        let historyBar = app.navigationBars["History"]
        XCTAssertTrue(historyBar.waitForExistence(timeout: 5))
        let allHistory = app.descendants(matching: .any)["historyList"].firstMatch
        let editedEntries = allHistory.staticTexts.matching(NSPredicate(format: "label == %@", edited))
        capture("\(layout)-08b-All-History-Before-Reveal", app: app)
        reveal(editedEntries.firstMatch, in: app, container: "historyList", requireCompleteFrame: false)
        XCTAssertTrue(editedEntries.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(editedEntries.count, 1,
                       "View all must show the same single saved thought as the recent shortcut.")
        capture("\(layout)-08c-All-History-Revealed", app: app)
        let historyDone = historyBar.buttons["Done"]
        assertNativeControl(historyDone, in: app)
        historyDone.tap()
        XCTAssertTrue(historyBar.waitForNonExistence(timeout: 5))
        assertCustomControl(record, in: app)
        reveal(recent, in: app, container: "transcriptScrollView")
        assertCustomControl(recent, in: app)
        recent.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.label, edited,
                       "Returning through History must not change the recent thought or its selected version.")

        let showOriginal = app.buttons["historyOriginalButton"]
        reveal(showOriginal, in: app, container: "historyDetailScrollView")
        assertCustomControl(showOriginal, in: app)
        showOriginal.tap()
        waitForLabel(detail, equalTo: original)
        showOriginal.tap()
        waitForLabel(detail, equalTo: edited)

        let rewrite = app.buttons["historyRewriteButton"]
        reveal(rewrite, in: app, container: "historyDetailScrollView")
        assertCustomControl(rewrite, in: app)
        rewrite.tap()
        let keepOriginal = app.buttons["history-rewrite-transcript"]
        XCTAssertTrue(keepOriginal.waitForExistence(timeout: 5))
        keepOriginal.tap()
        waitForLabel(result, equalTo: original, timeout: 10)
        assertCustomControl(record, in: app)
        capture("\(layout)-09-Original-Restored", app: app)

        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        let history = app.descendants(matching: .any)["historyList"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let saved = history.staticTexts.matching(NSPredicate(format: "label == %@", original))
        capture("\(layout)-09b-Rewritten-History-Before-Reveal", app: app)
        reveal(saved.firstMatch, in: app, container: "historyList", requireCompleteFrame: false)
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.count, 1,
                       "Editing and rewriting the recent thought must update one saved dictation.")
        capture("\(layout)-09c-Rewritten-History-Revealed", app: app)
        saved.firstMatch.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.label, original)
        capture("\(layout)-10-Verified-In-History", app: app)
    }

    private func assertCustomControl(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        // Accessibility coordinates can round a 44-point dimension to
        // 43.99999999999997. Ignore only floating-point noise, not undersizing.
        let geometryTolerance: CGFloat = 0.000_001
        XCTAssertGreaterThanOrEqual(element.frame.width + geometryTolerance, 44, "Narrow target: \(element.identifier)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + geometryTolerance, 44, "Short target: \(element.identifier)", file: file, line: line)
        assertNativeControl(element, in: app, file: file, line: line)
    }

    private func assertNativeControl(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame),
                      "Clipped control: \(element.identifier), \(element.frame)", file: file, line: line)
        XCTAssertTrue(element.isEnabled, file: file, line: line)
        XCTAssertTrue(element.isHittable, "Unreachable control: \(element.identifier)", file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, equalTo label: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed, file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, containing label: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, container identifier: String,
                        requireCompleteFrame: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        // Home also contains fixed controls outside its reading scroll view.
        if element.exists && element.isHittable && window.frame.contains(element.frame) { return }
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
            let distance = min(viewport.height * 0.4, max(20, abs(offset) * 0.5))
            let startY = viewport.minY + viewport.height * (offset > 0 ? 0.72 : 0.28)
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let x = viewport.minX + viewport.width * 0.82 - scroll.frame.minX
            let start = origin.withOffset(CGVector(dx: x, dy: startY - scroll.frame.minY))
            let end = origin.withOffset(CGVector(dx: x, dy: startY - scroll.frame.minY + (offset > 0 ? -distance : distance)))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Could not reveal \(element.identifier): \(element.frame)", file: file, line: line)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        // Native screen capture retains the rotated canvas on iOS 27.
        let screenshot = XCUIDevice.shared.orientation.isLandscape ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Reimagined-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
