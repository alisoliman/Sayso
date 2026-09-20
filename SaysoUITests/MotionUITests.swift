import XCTest
import UIKit

/// Standard tests inherit the system setting; Reduced Motion wrappers enable
/// and restore it through native Settings. The actual preference is recorded;
/// no launch argument overrides the app's accessibility environment. The native
/// XCTest screen recording supplies continuous transition evidence. Scripted
/// speech exercises the real UI/controller but does not assess recognition.
@MainActor
final class MotionUITests: XCTestCase {
    private var events: [String] = []
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var originalReduceMotion: Bool?
    private var motionName: String { UIAccessibility.isReduceMotionEnabled ? "Reduced" : "Standard" }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        startedAt = ProcessInfo.processInfo.systemUptime
        events = []
        originalReduceMotion = nil
        XCUIDevice.shared.orientation = .portrait
        event("System UIAccessibility.isReduceMotionEnabled = \(UIAccessibility.isReduceMotionEnabled)")
    }

    override func tearDown() {
        let exercisedMotionName = motionName
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        // XCTest invokes tearDown after a failed assertion even when an
        // Objective-C interruption bypasses Swift defer in the test body.
        // Keep restoration failures visible while still collecting evidence.
        if let originalReduceMotion {
            continueAfterFailure = true
            do {
                try setSystemReduceMotion(originalReduceMotion, preserveOriginal: false)
                event("Restored original system Reduce Motion = \(originalReduceMotion)")
            } catch {
                event("FAILED restoring system Reduce Motion: \(error)")
                XCTFail("Could not restore the original system Reduce Motion setting: \(error)")
            }
        }
        let timeline = XCTAttachment(string: events.joined(separator: "\n"))
        timeline.name = "Motion-\(exercisedMotionName)-Observed-Timeline"
        timeline.lifetime = .keepAlways
        add(timeline)
        super.tearDown()
    }

    func testReducedMotionRecordingRefinementResultAndCopyFeedback() throws {
        try setSystemReduceMotion(true, preserveOriginal: true)
        testRecordingRefinementResultAndCopyFeedbackWithSystemMotionSetting()
    }

    func testReducedMotionCancelAndImmediateRestart() throws {
        try setSystemReduceMotion(true, preserveOriginal: true)
        testCancelAndImmediateRestartDoNotRestoreStaleUIWithSystemMotionSetting()
    }

    func testCompactRecordingRefinementResultAndCopyFeedback() {
        XCUIDevice.shared.orientation = .landscapeLeft
        testRecordingRefinementResultAndCopyFeedbackWithSystemMotionSetting()
    }


    func testRecordingRefinementResultAndCopyFeedbackWithSystemMotionSetting() {
        let app = launch()
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        capture("Home", app: app)
        chooseClean(in: app)
        XCTAssertTrue(app.buttons["modeButton"].label.contains("Clean"))
        capture("Mode-Selected", app: app)

        event("Start recording requested")
        record.tap()
        waitForState(record, predicate: "enabled == true AND label == 'Stop recording'")
        XCTAssertFalse(app.buttons["historyButton"].isEnabled)
        let live = app.staticTexts["liveTranscript"]
        waitForState(live, predicate: "label ENDSWITH 'next project.'", timeout: 10)
        let capturedWords = live.label
        // The scripted source has now finished adding words. Sampling this
        // steady input makes the ongoing waveform motion visually comparable.
        captureSequence("Live-Steady-Input", app: app)

        event("Finish recording requested")
        record.tap()
        let refining = app.staticTexts["A little polish…"]
        XCTAssertTrue(refining.waitForExistence(timeout: 5))
        XCTAssertFalse(record.isEnabled)
        capture("Refining", app: app)
        waitForState(record, predicate: "enabled == true AND label == 'Start recording'", timeout: 10)
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, capturedWords)
        XCTAssertFalse(refining.exists)
        XCTAssertTrue(app.buttons["historyButton"].isEnabled)
        capture("Result", app: app)

        let copy = app.buttons["copyButton"]
        reveal(copy, in: app)
        let copyFrame = copy.frame
        event("Copy requested")
        copy.tap()
        waitForState(copy, predicate: "label CONTAINS 'Copied'")
        XCTAssertEqual(copy.frame.width, copyFrame.width, accuracy: 1,
                       "Copy confirmation must not push adjacent actions sideways.")
        XCTAssertEqual(copy.frame.minX, copyFrame.minX, accuracy: 1)
        captureSequence("Copy-Confirmation", app: app)
        waitForState(copy, predicate: "label == 'Copy'", timeout: 5)
        XCTAssertEqual(result.label, capturedWords, "Feedback must not mutate the writing.")
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(copy.isHittable)
        capture("Copy-Ready-Again", app: app)
    }

    func testCancelAndImmediateRestartDoNotRestoreStaleUIWithSystemMotionSetting() {
        let app = launch(slowRefinement: true)
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        chooseClean(in: app)
        record.tap()
        let live = app.staticTexts["liveTranscript"]
        waitForState(live, predicate: "label ENDSWITH 'next project.'", timeout: 10)
        let original = live.label
        let stopTime = ProcessInfo.processInfo.systemUptime
        event("Finish requested before cancelling slow refinement")
        record.tap()
        XCTAssertTrue(app.staticTexts["A little polish…"].waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.isHittable)
        event("Cancel refinement requested")
        cancel.tap()
        waitForState(record, predicate: "enabled == true AND label == 'Start recording'")
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - stopTime, 25,
                          "Cancellation must complete before the 30-second scripted transform.")
        XCTAssertEqual(app.staticTexts["resultText"].label, original)
        XCTAssertFalse(app.staticTexts["A little polish…"].exists)

        // Restart as soon as the actual action becomes enabled. The previous
        // asynchronous completion must not reappear over the next recording.
        event("Immediate new recording requested")
        record.tap()
        waitForState(record, predicate: "enabled == true AND label == 'Stop recording'")
        XCTAssertTrue(live.exists)
        XCTAssertFalse(app.staticTexts["resultText"].exists)
        XCTAssertFalse(app.staticTexts["A little polish…"].exists)
        captureSequence("Restart-After-Cancel", app: app)
        XCTAssertEqual(record.label, "Stop recording")

        let discard = app.buttons["discardRecordingButton"]
        XCTAssertTrue(discard.isHittable)
        discard.tap()
        let confirm = app.sheets.buttons["Discard recording"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        event("Discard new recording confirmed")
        confirm.tap()
        waitForState(record, predicate: "enabled == true AND label == 'Start recording'")
        XCTAssertTrue(app.staticTexts["homeHeadline"].exists)
        XCTAssertFalse(app.staticTexts["resultText"].exists)
        XCTAssertTrue(app.buttons["modeButton"].isEnabled)
        capture("Discarded-Ready", app: app)
        record.tap()
        waitForState(record, predicate: "enabled == true AND label == 'Stop recording'")
        XCTAssertTrue(live.exists)
        capture("Next-Recording", app: app)
    }

    private func launch(slowRefinement: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--scripted-speech", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if slowRefinement { app.launchArguments.append("--scripted-slow-refinement") }
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        let expectsLandscape = XCUIDevice.shared.orientation.isLandscape
        app.launch()
        if expectsLandscape {
            let window = app.windows.firstMatch
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                window.frame.width > window.frame.height
            }, object: window)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed,
                           "The compact motion journey must actually run in landscape.")
        }
        event("App launched; system Reduce Motion = \(UIAccessibility.isReduceMotionEnabled)")
        return app
    }

    private struct MotionSettingsError: Error, CustomStringConvertible {
        let description: String
    }

    private func setSystemReduceMotion(_ enabled: Bool, preserveOriginal: Bool) throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        if !settings.navigationBars["Motion"].exists {
            try returnToSettingsRoot(settings)
            try tapSettingsRow("Accessibility", in: settings)
            try tapSettingsRow("Motion", in: settings)
        }
        let toggle = settings.switches["Reduce Motion"].firstMatch
        guard toggle.waitForExistence(timeout: 5), toggle.isHittable,
              let value = toggle.value as? String, value == "0" || value == "1" else {
            recordSettingsFailure("The native Reduce Motion switch is unavailable.", settings: settings)
            throw MotionSettingsError(description: "The native Reduce Motion switch is unavailable.")
        }
        let current = value == "1"
        if preserveOriginal { originalReduceMotion = current }
        event("Native Settings Reduce Motion switch = \(current); requested \(enabled)")
        if current != enabled {
            // iOS 27 exposes the named Switch as a 330pt-wide label wrapper.
            // Its center does not toggle anything. The recorded native hierarchy
            // also exposes a narrow UISwitch aligned with that exact row.
            let rowFrame = toggle.frame
            let thumbs = settings.switches.allElementsBoundByIndex.filter { candidate in
                let frame = candidate.frame
                return frame.width < rowFrame.width * 0.5
                    && frame.minX > rowFrame.midX
                    && abs(frame.midY - rowFrame.midY) < 4
                    && rowFrame.insetBy(dx: -4, dy: -4).contains(frame)
                    && candidate.isHittable
            }
            guard thumbs.count == 1, let thumb = thumbs.first else {
                recordSettingsFailure("The Reduce Motion row does not expose one unambiguous native switch.", settings: settings)
                throw MotionSettingsError(description: "The Reduce Motion row does not expose one unambiguous native switch.")
            }
            event("Tapping the observed native Reduce Motion thumb at \(thumb.frame)")
            thumb.tap()
        }
        let switchMatches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        guard XCTWaiter.wait(for: [switchMatches], timeout: 5) == .completed else {
            recordSettingsFailure("Settings did not retain the requested Reduce Motion value.", settings: settings)
            throw MotionSettingsError(description: "Settings did not retain the requested Reduce Motion value.")
        }
        let systemMatches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            UIAccessibility.isReduceMotionEnabled == enabled
        }, object: nil)
        guard XCTWaiter.wait(for: [systemMatches], timeout: 5) == .completed else {
            recordSettingsFailure("UIKit did not observe the system Reduce Motion change.", settings: settings)
            throw MotionSettingsError(description: "UIKit did not observe the system Reduce Motion change.")
        }
        event("Verified native switch and UIAccessibility.isReduceMotionEnabled = \(enabled)")
        capture(enabled ? "System-Reduce-Motion-On" : "System-Reduce-Motion-Off", app: settings)
    }

    private func returnToSettingsRoot(_ settings: XCUIApplication) throws {
        // Return through the native Settings navigation stack.
        for _ in 0..<10 {
            if settings.searchFields.firstMatch.exists {
                let close = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "close"]))
                    .allElementsBoundByIndex.first { $0.exists && $0.isHittable }
                close?.tap()
            }
            if settings.navigationBars["Settings"].exists { return }
            let observedBack = settings.navigationBars.buttons["BackButton"]
            let back = observedBack.exists ? observedBack : settings.navigationBars.buttons.matching(NSPredicate(
                format: "label IN %@", ["Settings", "Accessibility", "Motion", "General", "Back"]
            )).firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
        }
        recordSettingsFailure("Could not return to the native Settings root.", settings: settings)
        throw MotionSettingsError(description: "Could not return to the native Settings root.")
    }

    private func tapSettingsRow(_ title: String, in settings: XCUIApplication) throws {
        for _ in 0..<16 {
            let window = settings.windows.firstMatch.frame
            let navigation = settings.navigationBars.firstMatch
            let top = max(window.minY, navigation.exists ? navigation.frame.maxY : window.minY) + 8
            let viewport = CGRect(x: window.minX, y: top, width: window.width,
                                  height: max(0, window.maxY - 48 - top))
            let candidates = [settings.buttons[title],
                              settings.cells.containing(.staticText, identifier: title).firstMatch,
                              settings.staticTexts[title]]
            if let target = candidates.first(where: { $0.exists && viewport.contains($0.frame) && $0.isHittable }) {
                target.tap()
                return
            }
            let target = candidates.first { $0.exists }
            let above = target.map { $0.frame.minY < viewport.minY } ?? false
            guard viewport.height > 80 else { break }
            // Stay within the native list and well above the Home indicator.
            let start = settings.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: viewport.minX + viewport.width * 0.82,
                         dy: viewport.minY + viewport.height * (above ? 0.3 : 0.72)))
            let end = settings.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: viewport.minX + viewport.width * 0.82,
                         dy: viewport.minY + viewport.height * (above ? 0.72 : 0.3)))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        recordSettingsFailure("Native Settings row '\(title)' is unreachable.", settings: settings)
        throw MotionSettingsError(description: "Native Settings row '\(title)' is unreachable.")
    }

    private func recordSettingsFailure(_ message: String, settings: XCUIApplication) {
        event(message)
        let hierarchy = XCTAttachment(string: settings.debugDescription)
        hierarchy.name = "Motion-System-Settings-Failure-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func chooseClean(in app: XCUIApplication) {
        app.buttons["modeButton"].tap()
        let clean = app.buttons["mode-clean"]
        XCTAssertTrue(clean.waitForExistence(timeout: 5))
        reveal(clean, in: app, container: "writingModesScrollView")
        capture("Mode-Choice", app: app)
        clean.tap()
        XCTAssertTrue(app.buttons["modeButton"].waitForExistence(timeout: 5))
    }

    private func waitForState(_ element: XCUIElement, predicate: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Did not reach \(predicate) for \(element.identifier)", file: file, line: line)
        event("Observed \(element.identifier): \(predicate)")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, container: String = "transcriptScrollView") {
        let scroll = app.scrollViews[container]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            XCTAssertEqual(app.state, .runningForeground)
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 2, dy: 4)
            if element.exists && element.isHittable && viewport.contains(element.frame) { return }
            let below = !element.exists || element.frame.midY > viewport.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: below ? 0.72 : 0.28))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: below ? 0.38 : 0.62))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Unreachable motion feedback control: \(element.identifier)")
    }

    private func captureSequence(_ name: String, app: XCUIApplication) {
        for frame in 0..<4 {
            capture("\(name)-Frame-\(frame)", app: app)
            if frame < 3 {
                // Pause only the test runner; the app continues animating. The
                // attached timeline records real capture times, not an assumed fps.
                Thread.sleep(forTimeInterval: 0.18)
            }
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        XCTAssertEqual(app.state, .runningForeground)
        event("Capture \(name)")
        // iOS 27's app-only landscape capture uses a cropped portrait canvas.
        // The native display screenshot preserves the actual rotated surface.
        let screenshot = XCUIDevice.shared.orientation.isLandscape ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Motion-\(motionName)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func event(_ description: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        events.append(String(format: "%.3f s | %@", elapsed, description))
    }
}
