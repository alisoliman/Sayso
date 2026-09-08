import XCTest
import UIKit

/// Exercises the real app UI and persistence with a DEBUG-only sample result.
/// These tests do not claim to verify microphone recognition or model quality.
@MainActor
final class SaysoUITests: XCTestCase {
    private func capture(_ name: String, app: XCUIApplication) {
        // iOS 27's app-only landscape capture was cropped onto a portrait
        // canvas. The native screen capture preserves the actual rotated UI.
        let screenshot = XCUIDevice.shared.orientation.isLandscape ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertFullyVisible(_ element: XCUIElement, in viewport: CGRect, enabled: Bool = true) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(viewport.contains(frame), "Clipped control: \(element.identifier), frame \(frame), viewport \(viewport)")
        if enabled { XCTAssertTrue(element.isEnabled) }
        XCTAssertTrue(element.isHittable, "Unreachable control: \(element.identifier)")
    }

    private func captureNativeBoundary(_ name: String, app: XCUIApplication) {
        capture(name, app: app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func launch(previewResult: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + (previewResult ? ["--preview-result"] : [])
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()
        return app
    }

    func testHomeModesSettingsAndEmptyHistoryAreReachable() {
        let app = launch()
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recordButton"].isEnabled)
        XCTAssertTrue(app.buttons["importButton"].exists)
        capture("01-Home", app: app)

        app.buttons["modeButton"].tap()
        let cleanMode = app.buttons["mode-clean"]
        XCTAssertTrue(cleanMode.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode-transcript"].exists)
        capture("02-Writing-Modes", app: app)
        cleanMode.tap()
        XCTAssertTrue(app.buttons["modeButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modeButton"].label.contains("Clean"))

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["saveHistoryToggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["languagePicker"].firstMatch.exists)
        capture("03-Settings", app: app)
        app.navigationBars.buttons["Done"].tap()

        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A place for your words"].exists)
        capture("04-Empty-History", app: app)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 5))
    }

    func testCustomModeCommitsOnlyValidDoneAndSwipeDismissPreservesSavedStyle() throws {
        continueAfterFailure = false
        let app = launch()
        let modeButton = app.buttons["modeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 10))
        let originalMode = modeButton.label

        func openCustomEditor() -> XCUIElement {
            modeButton.tap()
            let custom = app.buttons["mode-custom"]
            XCTAssertTrue(custom.waitForExistence(timeout: 5))
            custom.tap()
            let editor = app.textViews["customStyleInstructions"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            return editor
        }

        func swipeDismissEditorAndCloseModes() {
            let customBar = app.navigationBars["Custom mode"]
            var dismissed = false
            // With the keyboard open, the first drag can collapse the large
            // detent. A second drag dismisses the remaining medium sheet.
            for _ in 0..<2 {
                customBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
                dismissed = customBar.waitForNonExistence(timeout: 2)
                if dismissed { break }
            }
            XCTAssertTrue(dismissed, "The Custom editor must disappear before interacting with the underlying Modes sheet.")
            let modes = app.navigationBars["Modes"]
            XCTAssertTrue(modes.waitForExistence(timeout: 5))
            XCTAssertTrue(modes.buttons["Done"].isHittable)
            modes.buttons["Done"].tap()
            XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        }

        let emptyEditor = openCustomEditor()
        XCTAssertEqual(emptyEditor.value as? String, "")
        XCTAssertFalse(app.buttons["saveCustomStyleButton"].isEnabled)
        swipeDismissEditorAndCloseModes()
        XCTAssertEqual(modeButton.label, originalMode, "Cancelling an empty Custom editor must preserve the prior mode.")

        let editor = openCustomEditor()
        let savedStyle = "Use two short bullets."
        editor.tap()
        editor.typeText(savedStyle)
        XCTAssertTrue(app.buttons["saveCustomStyleButton"].isEnabled)
        app.buttons["saveCustomStyleButton"].tap()
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(modeButton.label.contains("Custom"))

        // Reload both bindings from preferences before testing cancellation of
        // an existing valid style; a saved Custom mode must remain usable.
        app.terminate()
        app.launch()
        XCTAssertTrue(modeButton.waitForExistence(timeout: 10))
        XCTAssertTrue(modeButton.label.contains("Custom"))
        let savedEditor = openCustomEditor()
        XCTAssertEqual(savedEditor.value as? String, savedStyle)
        capture("Custom-Saved-Before-Editing", app: app)
        XCTAssertTrue(app.buttons["saveCustomStyleButton"].isEnabled, "A saved nonempty style must enable Done before editing begins.")
        savedEditor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // The simulator's hardware Command-A event left the caret at the
        // beginning. Select the text through the visible native edit menu.
        savedEditor.press(forDuration: 1)
        let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Select All")).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), app.debugDescription)
        capture("Custom-Native-Edit-Menu", app: app)
        selectAll.tap()
        capture("Custom-Selected-Before-Deleting", app: app)
        let deleteKey = app.keyboards.keys["delete"]
        XCTAssertTrue(deleteKey.waitForExistence(timeout: 5), app.keyboards.debugDescription)
        deleteKey.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", ""), object: savedEditor)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        XCTAssertEqual(savedEditor.value as? String, "")
        XCTAssertFalse(app.buttons["saveCustomStyleButton"].isEnabled)
        capture("Custom-Empty-Draft-Before-Cancelling", app: app)
        swipeDismissEditorAndCloseModes()
        XCTAssertTrue(modeButton.label.contains("Custom"))
        let restoredEditor = openCustomEditor()
        XCTAssertEqual(restoredEditor.value as? String, savedStyle, "Interactive dismissal must discard an invalid draft without clearing saved instructions.")
        XCTAssertTrue(app.buttons["saveCustomStyleButton"].isEnabled)
    }

    func testResultCopyOriginalEditingAndHistorySurviveRelaunch() throws {
        let app = launch(previewResult: true)
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let refined = result.label
        XCTAssertTrue(app.buttons["importButton"].exists)
        capture("05-Result", app: app)

        app.buttons["originalButton"].tap()
        XCTAssertTrue(result.label.hasPrefix("um let's keep it simple"))
        XCTAssertNotEqual(result.label, refined)
        app.buttons["originalButton"].tap()
        XCTAssertEqual(result.label, refined)

        let copy = app.buttons["copyButton"]
        copy.tap()
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Copied"), object: copy)
        XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 3), .completed)

        app.buttons["editButton"].tap()
        let editor = app.textViews["editText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, refined)
        XCTAssertTrue(app.buttons["saveEditButton"].isEnabled,
                      "The loaded nonempty text must enable Save before editing begins.")
        capture("Edit-Loaded-Text-Ready-To-Save", app: app)
        editor.tap()
        editor.typeText("\nA thought worth keeping.")
        let edited = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(edited.contains("A thought worth keeping."))
        app.buttons["saveEditButton"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, edited)

        // The preview is deliberately not seeded on relaunch. The history must come from disk.
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["historyButton"].waitForExistence(timeout: 10))
        app.buttons["historyButton"].tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", edited)).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        capture("06-Saved-History", app: app)
        saved.tap()
        XCTAssertTrue(app.buttons["Show original"].waitForExistence(timeout: 5))
        app.buttons["Show original"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "um let's keep it simple")).firstMatch.exists)
        app.buttons["historyRewriteButton"].tap()
        app.buttons["history-rewrite-transcript"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.hasPrefix("um let's keep it simple"))
        XCTAssertTrue(app.buttons["recordButton"].isEnabled)
    }

    func testCancellingEditLeavesDisplayedTextUnchanged() {
        let app = launch(previewResult: true)
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let before = result.label
        app.buttons["editButton"].tap()
        let editor = app.textViews["editText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" This edit will be cancelled.")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, before)
    }

    func testDarkAppearanceKeepsRecordingActionAccessible() {
        // The verification script sets the real simulator appearance to dark for this test.
        // iOS does not honor a macOS-style AppleInterfaceStyle launch argument.
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recordButton"].isHittable)
        capture("07-Home-Dark", app: app)
    }

    func testAccessibilityTextSizeKeepsRecordingActionAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recordButton"].isHittable)
        let crossAppRecording = app.buttons["keyboardRecordButton"]
        XCTAssertTrue(crossAppRecording.waitForExistence(timeout: 5))
        XCTAssertEqual(crossAppRecording.label, "Dictate in another app")
        XCTAssertTrue(crossAppRecording.isEnabled)
        XCTAssertTrue(crossAppRecording.isHittable)
        capture("08-Home-Accessibility-XXXL", app: app)

        app.terminate()
        app.launchArguments.append("--preview-result")
        app.launch()
        XCTAssertTrue(app.staticTexts["resultText"].waitForExistence(timeout: 10))
        capture("08b-Result-Accessibility-XXXL", app: app)
        // At this text size the controls form a vertical list. Require every
        // action to be reachable in order, without requiring them all onscreen.
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        let actions = [
            ("copyButton", "08c-Copy-Accessibility-XXXL"),
            ("editButton", "08c-Edit-Accessibility-XXXL"),
            ("sendToKeyboardButton", "08c-Keyboard-Accessibility-XXXL"),
            ("importButton", "08c-Result-Actions-Accessibility-XXXL")
        ]
        for (identifier, screenshot) in actions {
            let action = app.buttons[identifier]
            XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing accessibility action: \(identifier)")
            for _ in 0..<16 {
                let viewport = scroll.frame.insetBy(dx: 0, dy: 4)
                if viewport.contains(action.frame) && action.isHittable { break }
                let aboveViewport = action.frame.minY < viewport.minY
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: aboveViewport ? 0.35 : 0.70))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: aboveViewport ? 0.60 : 0.45))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            let viewport = scroll.frame.insetBy(dx: 0, dy: 4)
            XCTAssertTrue(viewport.contains(action.frame), "Accessibility action is clipped after bounded scrolling: \(identifier), frame \(action.frame), viewport \(viewport)")
            XCTAssertTrue(action.isEnabled, "Accessibility action is disabled: \(identifier)")
            XCTAssertTrue(action.isHittable, "Accessibility action is unreachable after bounded scrolling: \(identifier)")
            if identifier == "copyButton" {
                action.tap()
                let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Copied"), object: action)
                XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 3), .completed)
            }
            capture(screenshot, app: app)
        }
        XCTAssertEqual(crossAppRecording.label, "Dictate in another app")
        XCTAssertTrue(crossAppRecording.isHittable, "Cross-app recording must remain reachable while reviewing a result.")
    }

    func testLandscapeKeepsHomeRecordingAndLongResultAccessibleAtNormalAndLargestText() {
        continueAfterFailure = false
        // XCTest can abort a failed assertion through Objective-C without
        // unwinding Swift defer. Register cleanup with XCTest as well.
        addTeardownBlock {
            await MainActor.run {
                XCUIApplication().terminate()
                XCUIDevice.shared.orientation = .portrait
            }
        }
        var activeApp: XCUIApplication?
        defer {
            activeApp?.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let textSizes = [
            (name: "Normal", category: "UICTContentSizeCategoryL"),
            (name: "AX-XXXL", category: "UICTContentSizeCategoryAccessibilityXXXL")
        ]
        let orientations: [(name: String, value: UIDeviceOrientation)] = [
            ("Left", .landscapeLeft), ("Right", .landscapeRight)
        ]

        for textSize in textSizes {
            for orientation in orientations {
                XCUIDevice.shared.orientation = .portrait
                let app = XCUIApplication()
                activeApp = app
                app.launchArguments = ["--uitesting", "--scripted-speech", "--scripted-long",
                                       "-UIPreferredContentSizeCategoryName", textSize.category]
                app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
                app.launch()
                let record = app.buttons["recordButton"]
                XCTAssertTrue(record.waitForExistence(timeout: 10))
                XCUIDevice.shared.orientation = orientation.value
                let window = app.windows.firstMatch
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    window.frame.width > window.frame.height
                }, object: window)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)

                let scroll = app.scrollViews["transcriptScrollView"]
                XCTAssertTrue(scroll.waitForExistence(timeout: 5))
                // A useful reading area must remain between header and controls;
                // the old portrait stack left only a sliver in landscape.
                XCTAssertGreaterThanOrEqual(scroll.frame.height, 180, "Landscape must retain space for multiple lines of writing.")
                let viewport = scroll.frame.intersection(window.frame).insetBy(dx: 2, dy: 2)
                assertFullyVisible(app.staticTexts["Speak freely."], in: viewport, enabled: false)
                assertFullyVisible(app.buttons["importButton"], in: viewport)
                let mode = app.buttons["modeButton"]
                let crossApp = app.buttons["keyboardRecordButton"]
                for control in [mode, record, crossApp] {
                    assertFullyVisible(control, in: window.frame)
                    XCTAssertLessThanOrEqual(scroll.frame.maxY, control.frame.minY,
                                             "Recording controls must not cover the scroll viewport.")
                }
                XCTAssertEqual(crossApp.label, "Dictate in another app")
                let captureName = "Landscape-\(textSize.name)-\(orientation.name)"
                capture("\(captureName)-Home", app: app)
                // The wide plain mode button must respond at its center, not
                // only where its text happens to be drawn.
                mode.tap()
                let modes = app.navigationBars["Modes"]
                XCTAssertTrue(modes.waitForExistence(timeout: 5), "Tapping the full mode control must open Modes.")
                let done = modes.buttons["Done"]
                assertFullyVisible(done, in: window.frame)
                done.tap()
                XCTAssertTrue(modes.waitForNonExistence(timeout: 5))

                record.tap()
                let live = app.staticTexts["liveTranscript"]
                let allWords = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label ENDSWITH %@", "time to think."), object: live)
                XCTAssertEqual(XCTWaiter.wait(for: [allWords], timeout: 15), .completed)
                let expectedText = live.label
                XCTAssertGreaterThan(expectedText.count, 500, "This regression requires a long transcript.")
                XCTAssertGreaterThanOrEqual(scroll.frame.height, 180)
                XCTAssertGreaterThanOrEqual(live.frame.intersection(scroll.frame).height, 100,
                                            "Latest-word following must leave readable text above the waveform.")
                XCTAssertEqual(record.label, "Stop recording")
                let discard = app.buttons["discardRecordingButton"]
                assertFullyVisible(record, in: window.frame)
                assertFullyVisible(discard, in: window.frame)
                capture("\(captureName)-Recording", app: app)
                discard.tap()
                let keep = app.buttons["Keep recording"]
                if keep.waitForExistence(timeout: 1) {
                    assertFullyVisible(keep, in: window.frame)
                    keep.tap()
                } else {
                    // Native landscape confirmation is a popover: it omits
                    // the cancel action and exposes an outside dismiss region.
                    let popover = app.popovers.firstMatch
                    XCTAssertTrue(popover.waitForExistence(timeout: 5))
                    assertFullyVisible(popover.buttons["Discard recording"], in: window.frame)
                    let dismissRegion = app.otherElements["PopoverDismissRegion"]
                    XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
                    let available = dismissRegion.frame.intersection(window.frame).insetBy(dx: 24, dy: 24)
                    let exclusion = popover.frame.insetBy(dx: -12, dy: -12)
                    let candidates = [
                        CGPoint(x: available.midX, y: available.minY + 16),
                        CGPoint(x: available.midX, y: available.maxY - 16),
                        CGPoint(x: available.minX + 60, y: available.midY),
                        CGPoint(x: available.maxX - 60, y: available.midY)
                    ]
                    guard let point = candidates.first(where: { available.contains($0) && !exclusion.contains($0) }) else {
                        XCTFail("No visible point outside the native discard popover.")
                        return
                    }
                    dismissRegion.coordinate(withNormalizedOffset: .zero).withOffset(
                        CGVector(dx: point.x - dismissRegion.frame.minX, dy: point.y - dismissRegion.frame.minY)).tap()
                    XCTAssertTrue(popover.waitForNonExistence(timeout: 5))
                }
                XCTAssertEqual(record.label, "Stop recording")
                record.tap()
                let result = app.staticTexts["resultText"]
                XCTAssertTrue(result.waitForExistence(timeout: 10))
                XCTAssertEqual(result.label, expectedText, "Rotation and the discard dialog must not lose captured words.")
                XCTAssertGreaterThanOrEqual(scroll.frame.height, 180)

                let copy = app.buttons["copyButton"]
                XCTAssertTrue(copy.waitForExistence(timeout: 5))
                // Long AX text spans many viewports. Scroll only the reading
                // surface and require the complete action before the actual tap.
                for _ in 0..<80 {
                    let visible = scroll.frame.intersection(window.frame).insetBy(dx: 2, dy: 2)
                    let target = copy.frame
                    if visible.contains(target) && copy.isHittable { break }
                    // Fixed 127pt drags oscillated around the 92pt AX action
                    // when it needed only 35pt to fit. Move toward its measured
                    // center, with damped nearby motion and no release flick.
                    let offset = target.midY - visible.midY
                    let distance = min(visible.height * 0.6, max(12, abs(offset) * 0.5))
                    let startY = offset > 0 ? visible.maxY - 12 : visible.minY + 12
                    let endY = startY + (offset > 0 ? -distance : distance)
                    let origin = scroll.coordinate(withNormalizedOffset: .zero)
                    let x = visible.maxX - scroll.frame.minX - 24
                    let start = origin.withOffset(CGVector(dx: x, dy: startY - scroll.frame.minY))
                    let end = origin.withOffset(CGVector(dx: x, dy: endY - scroll.frame.minY))
                    start.press(forDuration: 0.05, thenDragTo: end,
                                withVelocity: abs(offset) < visible.height ? .slow : .default,
                                thenHoldForDuration: 0.25)
                }
                assertFullyVisible(copy, in: scroll.frame.intersection(window.frame).insetBy(dx: 2, dy: 2))
                copy.tap()
                let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Copied"), object: copy)
                XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 3), .completed)
                capture("\(captureName)-Copied-Long-Result", app: app)
                app.terminate()
                activeApp = nil
            }
        }
    }

    func testCompactRefinementCancelPreservesOriginalAndAllowsNextRecording() {
        continueAfterFailure = false
        addTeardownBlock {
            await MainActor.run {
                XCUIApplication().terminate()
                XCUIDevice.shared.orientation = .portrait
            }
        }
        let orientations: [(name: String, value: UIDeviceOrientation)] = [
            ("Left", .landscapeLeft), ("Right", .landscapeRight)
        ]
        for orientation in orientations {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting", "--scripted-speech", "--scripted-slow-refinement",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
            app.launch()
            let record = app.buttons["recordButton"]
            XCTAssertTrue(record.waitForExistence(timeout: 10))
            app.buttons["modeButton"].tap()
            let clean = app.buttons["mode-clean"]
            XCTAssertTrue(clean.waitForExistence(timeout: 5))
            clean.tap()
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            XCUIDevice.shared.orientation = orientation.value
            let window = app.windows.firstMatch
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                window.frame.width > window.frame.height
            }, object: window)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            assertFullyVisible(record, in: window.frame)
            record.tap()
            let live = app.staticTexts["liveTranscript"]
            let allWords = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label ENDSWITH %@", "next project."), object: live)
            XCTAssertEqual(XCTWaiter.wait(for: [allWords], timeout: 10), .completed)
            let original = live.label
            XCTAssertFalse(original.isEmpty)
            XCTAssertEqual(record.label, "Stop recording")

            // The explicit 30-second transform makes this an actual Cancel
            // check. Natural completion cannot satisfy the earlier deadline.
            let stoppedAt = Date()
            record.tap()
            let refining = app.staticTexts["A little polish…"]
            XCTAssertTrue(refining.waitForExistence(timeout: 5))
            let cancel = app.buttons["Cancel"]
            assertFullyVisible(cancel, in: window.frame)
            capture("Landscape-AX-XXXL-\(orientation.name)-Refinement-Cancel", app: app)
            cancel.tap()
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true AND label == %@", "Start recording"), object: record)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            XCTAssertLessThan(Date().timeIntervalSince(stoppedAt), 25,
                              "The 30-second scripted generation must still be pending when Cancel returns to idle.")
            XCTAssertFalse(refining.exists)
            XCTAssertFalse(cancel.exists)
            XCTAssertEqual(app.staticTexts["resultText"].label, original)
            XCTAssertTrue(app.buttons["modeButton"].isEnabled)
            capture("Landscape-AX-XXXL-\(orientation.name)-Cancelled-Original", app: app)

            assertFullyVisible(record, in: window.frame)
            record.tap()
            let listeningAgain = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true AND label == %@", "Stop recording"), object: record)
            XCTAssertEqual(XCTWaiter.wait(for: [listeningAgain], timeout: 5), .completed)
            XCTAssertTrue(live.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["historyButton"].isEnabled)
            // The replacement is an isolated audio-free preview. Terminating
            // it ends that fake capture without publishing or sharing anything.
            app.terminate()
        }
    }

    func testNativeShareAndImportCancellationPreservePreview() {
        continueAfterFailure = false
        addTeardownBlock {
            await MainActor.run {
                XCUIApplication().terminate()
                XCUIDevice.shared.orientation = .portrait
            }
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-result",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let original = result.label
        XCTAssertFalse(original.isEmpty)
        let window = app.windows.firstMatch
        let share = app.buttons["Share text"]
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertFalse(shareSheet.exists)
        assertFullyVisible(share, in: window.frame)
        share.tap()

        // Inspect only the system action sheet; never choose a recipient or
        // an action that exports the synthetic text.
        let shareAppeared = shareSheet.waitForExistence(timeout: 5)
        captureNativeBoundary("Native-Share-Presented", app: app)
        XCTAssertTrue(shareAppeared, "The native Share activity view did not appear; inspect the retained hierarchy.")
        XCTAssertTrue(shareSheet.otherElements["ShareSheet.RemoteContainerView"].exists)
        XCTAssertEqual(shareSheet.otherElements["LP.CaptionBar.BottomCaption"].label, original,
                       "The native Share preview must receive the exact synthetic source.")
        // iOS 27 presents this as a popover without Close. Its observed native
        // dismiss region covers the host; choose a point above the popover,
        // outside every recipient and action in the sharing surface.
        let sharePopover = app.popovers.firstMatch
        XCTAssertTrue(sharePopover.exists)
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.exists)
        let available = dismissRegion.frame.intersection(window.frame).insetBy(dx: 24, dy: 24)
        let exclusion = sharePopover.frame.insetBy(dx: -12, dy: -12)
        let point = CGPoint(x: available.midX, y: (available.minY + exclusion.minY) / 2)
        XCTAssertTrue(available.contains(point), "Share must expose a visible native dismissal region.")
        XCTAssertFalse(exclusion.contains(point), "Dismissal must be outside the sharing popover.")
        dismissRegion.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x - dismissRegion.frame.minX, dy: point.y - dismissRegion.frame.minY)).tap()
        XCTAssertTrue(shareSheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(sharePopover.waitForNonExistence(timeout: 5))
        XCTAssertEqual(result.label, original)
        XCTAssertTrue(app.buttons["recordButton"].isEnabled)
        XCTAssertTrue(app.buttons["copyButton"].isEnabled)

        let importAudio = app.buttons["importButton"]
        let cancelImport = app.navigationBars.buttons["Cancel"].firstMatch
        XCTAssertFalse(cancelImport.exists)
        assertFullyVisible(importAudio, in: window.frame)
        importAudio.tap()
        // A native run captured a blank presented sheet after five seconds.
        // Allow bounded readiness; its cause is unproven and Cancel is still required.
        let importAppeared = cancelImport.waitForExistence(timeout: 15)
        captureNativeBoundary("Native-Import-Picker-Presented", app: app)
        XCTAssertTrue(importAppeared, "The native audio picker did not expose navigation Cancel; inspect the retained hierarchy.")
        assertFullyVisible(cancelImport, in: window.frame)
        cancelImport.tap()
        XCTAssertTrue(cancelImport.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Couldn’t complete dictation"].exists,
                       "Cancelling file selection must not report a failed dictation.")
        XCTAssertEqual(result.label, original)
        for control in [app.buttons["recordButton"], app.buttons["copyButton"], importAudio] {
            assertFullyVisible(control, in: window.frame)
        }
        capture("Native-Share-And-Import-Cancelled-Preview", app: app)
    }

    /// Run with microphone access denied for the dedicated simulator. This uses the real service;
    /// it never grants access, downloads a model, or supplies a fake recognition response.
    func testRecordingDeniedOrUnavailableRestoresUsableHome() {
        let app = launch()
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()

        let error = app.alerts["Couldn’t complete dictation"]
        if !error.waitForExistence(timeout: 3) {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Don't Allow", "Don’t Allow"])).firstMatch
            if deny.waitForExistence(timeout: 3) { deny.tap() }
        }
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        let message = error.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ").lowercased()
        XCTAssertTrue(message.contains("microphone") || message.contains("isn’t available") || message.contains("isn't available"), message)
        capture("09-Recording-Unavailable-Or-Denied", app: app)
        error.buttons["OK"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(record.isEnabled)
        XCTAssertTrue(app.buttons["historyButton"].isEnabled)
    }

    private func launchScripted(long: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--scripted-speech"] + (long ? ["--scripted-long"] : [])
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()
        return app
    }

    /// Drives real view/controller transitions with a clearly isolated scripted service.
    func testScriptedRecordingFinishingRefinementAndResult() {
        let app = launchScripted()
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 10))
        app.buttons["modeButton"].tap()
        app.buttons["mode-clean"].tap()
        app.buttons["recordButton"].tap()
        let live = app.staticTexts["liveTranscript"]
        let finishedWords = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "next project."), object: live)
        XCTAssertEqual(XCTWaiter.wait(for: [finishedWords], timeout: 10), .completed)
        XCTAssertEqual(app.buttons["recordButton"].label, "Stop recording")
        XCTAssertFalse(app.buttons["historyButton"].isEnabled)
        capture("11-Scripted-Recording", app: app)
        app.buttons["recordButton"].tap()
        XCTAssertTrue(app.staticTexts["A little polish…"].waitForExistence(timeout: 5))
        capture("12-Scripted-Refinement", app: app)
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["copyButton"].waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["recordButton"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertTrue(result.label.hasSuffix("next project."))
        app.buttons["historyButton"].tap()
        XCTAssertFalse(app.staticTexts["A place for your words"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "next project.")).firstMatch.exists)
    }

    func testScriptedLongRecordingCanReviewAndResumeLatestWords() {
        let app = launchScripted(long: true)
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 10))
        app.buttons["recordButton"].tap()
        let live = app.staticTexts["liveTranscript"]
        let allWords = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "time to think."), object: live)
        XCTAssertEqual(XCTWaiter.wait(for: [allWords], timeout: 15), .completed)
        capture("13-Scripted-Long-Recording-Latest", app: app)
        XCTAssertFalse(app.buttons["latestWordsButton"].exists)
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertTrue(app.buttons["latestWordsButton"].waitForExistence(timeout: 5))
        capture("14-Scripted-Long-Recording-Review", app: app)
        app.buttons["latestWordsButton"].tap()
        XCTAssertFalse(app.buttons["latestWordsButton"].exists)
        app.buttons["recordButton"].tap()
        XCTAssertTrue(app.staticTexts["resultText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recordButton"].isHittable)
    }

    func testScriptedDiscardDoesNotLeaveHistoryOrDisableNextRecording() {
        let app = launchScripted()
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 10))
        app.buttons["recordButton"].tap()
        XCTAssertTrue(app.staticTexts["liveTranscript"].waitForExistence(timeout: 5))
        app.buttons["Discard recording"].tap()
        XCTAssertTrue(app.sheets.buttons["Discard recording"].waitForExistence(timeout: 5))
        app.sheets.buttons["Discard recording"].tap()
        XCTAssertTrue(app.staticTexts["Speak freely."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recordButton"].isEnabled)
        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.staticTexts["A place for your words"].waitForExistence(timeout: 5))
    }

    func testExplicitKeyboardSharingAndSetupAreReachable() {
        let app = launch(previewResult: true)
        let send = app.buttons["sendToKeyboardButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertTrue(send.isHittable)
        XCTAssertLessThan(app.buttons["copyButton"].frame.height, 70, "Copy must stay on one line at the default text size.")
        capture("15-Result-With-Keyboard-Sharing", app: app)
        send.tap()
        let ready = app.alerts["Ready in your keyboard"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5), "The signed simulator build must have a working App Group.")
        capture("16-Keyboard-Handoff-Ready", app: app)
        ready.buttons["OK"].tap()
        app.buttons["settingsButton"].tap()
        let setup = app.buttons["Sayso keyboard"]
        for _ in 0..<4 {
            if setup.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(setup.isHittable)
        setup.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Full Access can stay off for inserting")).firstMatch.waitForExistence(timeout: 5))
        capture("17-Keyboard-Setup", app: app)
        let clear = app.buttons["Clear shared text"]
        for _ in 0..<3 {
            if clear.isHittable { break }
            app.swipeUp()
        }
        clear.tap()
        XCTAssertTrue(app.alerts["Shared text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["The text shared with your keyboard has been removed."].exists)
    }
    /// Uses a real ActivityKit request and App Group with scripted speech. It
    /// checks app state across a brief background visit, not real audio capture.
    func testScriptedKeyboardRecordingSurvivesBackgroundAndPreparesInsertion() {
        XCUIDevice.shared.orientation = .portrait
        let app = launchScripted()
        let start = app.buttons["keyboardRecordButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let live = app.staticTexts["liveTranscript"]
        XCTAssertTrue(live.waitForExistence(timeout: 8), "Keyboard recording must successfully start a real Live Activity.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Stop from the Live Activity")).firstMatch.exists)
        capture("18-Cross-App-Recording", app: app)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.icons["Sayso"].waitForExistence(timeout: 5))
        // Observe the widget's own label when SpringBoard exposes it. Its native
        // accessibility topology is not a contract, so a missing label is diagnostic.
        let duration = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Recording duration")).firstMatch
        let durationVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard duration.exists else { return false }
            let frame = duration.frame
            return frame.width > 0 && frame.height > 0
                && springboard.frame.contains(frame)
        }, object: nil)
        let observation = XCTWaiter.wait(for: [durationVisible], timeout: 3)
        // Capture the actual system surface; an app screenshot can omit its overlay.
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        home.name = "19-Cross-App-Home"
        home.lifetime = .keepAlways
        add(home)
        let observationText = observation == .completed
            ? "Recording duration label observed on screen."
            : "Recording duration label not observed within 3 seconds; inspect the native capture."
        let hierarchy = XCTAttachment(string: observationText + "\n\n" + springboard.debugDescription)
        hierarchy.name = "19-Cross-App-Home-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        app.activate()
        XCTAssertTrue(live.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["recordButton"].label, "Stop recording")
        let captured = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "next project."), object: live)
        XCTAssertEqual(XCTWaiter.wait(for: [captured], timeout: 10), .completed)
        app.buttons["recordButton"].tap()
        XCTAssertTrue(app.staticTexts["resultText"].waitForExistence(timeout: 8))
        let ready = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ready in the Sayso keyboard")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Couldn’t complete dictation"].exists)
        capture("20-Cross-App-Ready", app: app)
    }

    func testScriptedLiveActivityStopFromNotificationCenter() {
        let app = launchScripted()
        XCTAssertTrue(app.buttons["keyboardRecordButton"].waitForExistence(timeout: 10))
        app.buttons["keyboardRecordButton"].tap()
        let live = app.staticTexts["liveTranscript"]
        let captured = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH %@", "next project."), object: live)
        XCTAssertEqual(XCTWaiter.wait(for: [captured], timeout: 10), .completed)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.icons["Sayso"].waitForExistence(timeout: 5))
        // Pull from the observed status-bar edge to reveal Notification Center.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.75)))
        for label in ["Allow", "Always Allow"] {
            let allow = springboard.buttons[label]
            if allow.exists && allow.isHittable { allow.tap() }
        }
        let stop = springboard.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8), springboard.debugDescription)
        capture("21-Live-Activity-Controls", app: springboard)
        guard stop.exists else { app.activate(); return }
        stop.tap()
        app.activate()
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(result.label.hasSuffix("next project."))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ready in the Sayso keyboard")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Couldn’t complete dictation"].exists)
    }

}
