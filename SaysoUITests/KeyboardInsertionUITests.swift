import XCTest

/// Enables the installed keyboard using only Settings UI on the dedicated simulator.
/// The text is a DEBUG fixture explicitly published through Sayso's real App Group.
/// Settings search or Sayso's isolated editor is the destination; no text is sent.
@MainActor
final class KeyboardInsertionUITests: XCTestCase {
    private var sayso: XCUIApplication!
    private var settings: XCUIApplication!
    private var usesControlFixture = false
    private var launchedScriptedFixture = false
    private var ownsSharedFixture = false
    private var ownsSettingsSearch = false
    private var needsFullAccessRestoration = false
    private var cleanupAttempted = false
    private var ownsSaysoEditor = false
    private var restoresLandscapeEnvironment = false
    private var landscapeAppearanceAtStart = XCUIDevice.shared.appearance
    private var safariControlHost: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        sayso = XCUIApplication()
        settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    }

    override func tearDownWithError() throws {
        let previousContinuation = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousContinuation }
        if let testRun, testRun.failureCount > 0 {
            diagnose("Keyboard-Insertion-Failure", app: settings)
            diagnose("Sayso-Handoff-Failure", app: sayso)
            diagnose("System-Keyboard-Failure", app: XCUIApplication(bundleIdentifier: "com.apple.springboard"))
            if let safariControlHost { diagnose("Safari-Keyboard-Control-Failure", app: safariControlHost) }
        }
        if usesControlFixture, !cleanupAttempted {
            // Every cleanup stage is attempted and its failures remain XCTest
            // failures. A failed command assertion is never replaced by a retry.
            try cleanupControlFixture()
        }
    }

    func testExplicitInsertionInSettingsWithFullAccessOff() throws {
        usesControlFixture = true
        settings.launch()
        try enableSaysoWithFullAccessOff()

        sayso.launchArguments = ["--uitesting", "--preview-result"]
        sayso.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        sayso.launch()
        let result = sayso.staticTexts["resultText"]
        try require(result.waitForExistence(timeout: 10), "Sayso did not show its explicit preview result.", app: sayso)
        let expectedText = result.label
        try require(!expectedText.isEmpty, "The preview result must contain text.", app: sayso)
        let publish = sayso.buttons["sendToKeyboardButton"]
        try require(publish.waitForExistence(timeout: 5) && publish.isHittable,
                    "Send to keyboard is not reachable.", app: sayso)
        publish.tap()
        let ready = sayso.alerts["Ready in your keyboard"]
        try require(ready.waitForExistence(timeout: 5), "The real App Group publication did not succeed.", app: sayso)
        ownsSharedFixture = true
        ready.buttons["OK"].tap()

        settings.activate()
        try returnToSettingsRoot()
        let search = try openSettingsSearch()
        try clearSearch(search)
        ownsSettingsSearch = true
        try selectSaysoKeyboard()
        let insert = settings.buttons["keyboardInsertButton"]
        // Observed cold OS extension setup exceeded five seconds before UIKit
        // created our controller. Keep this first appearance wait bounded.
        try require(insert.waitForExistence(timeout: 15), "The Sayso extension did not appear in Settings.", app: settings)
        try require(waitFor(insert, predicate: "enabled == true", timeout: 5),
                    "The read-only keyboard could not load the explicitly shared text.", app: settings)
        XCTAssertEqual(contents(of: search), "", "Opening the keyboard must not insert any text automatically.")
        XCTAssertEqual(insert.label, "Insert")
        diagnose("Keyboard-Ready-Full-Access-Off", app: settings)

        // Use the extension's actual buttons, not typeText's synthesized input.
        settings.buttons["keyboardKey-q"].tap()
        try expectValue("q", in: search)
        settings.buttons["keyboardSpaceButton"].tap()
        try expectValue("q ", in: search)
        settings.buttons["keyboardDeleteButton"].tap()
        try expectValue("q", in: search)
        settings.buttons["keyboardDeleteButton"].tap()
        XCTAssertEqual(contents(of: search), "")
        XCTAssertTrue(insert.isEnabled, "Ordinary typing must not consume a shared dictation.")

        insert.tap()
        try expectValue(expectedText, in: search)
        try require(waitFor(insert, predicate: "enabled == false AND label == 'Inserted'", timeout: 5),
                    "The keyboard did not mark this publication as consumed.", app: settings)
        diagnose("Keyboard-Exact-Text-Inserted", app: settings)

        // Verify the normal input-mode control works, then that reopening Sayso
        // neither duplicates the text nor makes the same publication insertable.
        try switchToSystemKeyboard()
        try expectValue(expectedText, in: search)
        try selectSaysoKeyboard()
        try require(insert.waitForExistence(timeout: 5), "Sayso did not reopen through the input-mode menu.", app: settings)
        try require(waitFor(insert, predicate: "enabled == false AND label == 'Inserted'", timeout: 5),
                    "Reopening the keyboard must retain consumption state.", app: settings)
        try expectValue(expectedText, in: search)
        diagnose("Keyboard-Consumed-After-Reopening", app: settings)

        try cleanupControlFixture()
    }

    /// Run at both system Large and system AX XXXL. A host-only launch argument
    /// cannot establish the keyboard extension's actual content-size category.
    func testKeyboardReadyAndExactInsertionInBothLandscapeOrientations() throws {
        usesControlFixture = true
        restoresLandscapeEnvironment = true
        needsFullAccessRestoration = true
        landscapeAppearanceAtStart = XCUIDevice.shared.appearance
        XCUIDevice.shared.orientation = .portrait
        sayso.launchArguments = ["--uitesting", "--preview-result"]
        sayso.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        sayso.launch()
        let result = sayso.staticTexts["resultText"]
        try require(result.waitForExistence(timeout: 10), "The isolated preview result did not load.", app: sayso)
        let expectedText = result.label
        try require(!expectedText.isEmpty, "The synthetic preview must be nonempty.", app: sayso)

        // Replace the preceding manual synthetic publication before permission
        // setup, so any later failure can clear this test's own publication.
        try publishLandscapePreview()
        settings.launch()
        try enableSaysoWithFullAccessOff()
        sayso.activate()
        var editor = try prepareLandscapeEditor()
        let orientations: [(String, UIDeviceOrientation)] = [
            ("Left", .landscapeLeft), ("Right", .landscapeRight)
        ]

        func rotate(_ orientation: UIDeviceOrientation) throws {
            XCUIDevice.shared.orientation = orientation
            let window = sayso.windows.firstMatch
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                window.frame.width > window.frame.height
            }, object: window)
            try require(XCTWaiter.wait(for: [rotated], timeout: 5) == .completed,
                        "Sayso's editor did not reach landscape.", app: sayso)
        }

        // Capture both baseline orientations before reporting layout failures.
        // Do not interact with clipped controls merely because AX finds a sliver.
        var layoutFailures: [String] = []
        for (name, orientation) in orientations {
            try rotate(orientation)
            diagnose("Keyboard-Landscape-\(name)-Ready", app: sayso)
            let window = sayso.windows.firstMatch.frame
            let customGlobe = sayso.buttons["keyboardNextButton"]
            let usesCustomGlobe = customGlobe.exists && customGlobe.isHittable
            let globe = usesCustomGlobe ? customGlobe : inputModeButton(in: sayso)
            let controls = [
                ("Q", sayso.buttons["keyboardKey-q"]),
                ("Delete", sayso.buttons["keyboardDeleteButton"]),
                ("Return", sayso.buttons["keyboardReturnButton"]),
                ("Insert", sayso.buttons["keyboardInsertButton"]),
                ("Globe", globe),
                ("Save", sayso.buttons["saveEditButton"]),
                ("Cancel", sayso.navigationBars["Edit text"].buttons["Cancel"])
            ]
            for (label, control) in controls {
                guard control.exists else { layoutFailures.append("\(name): missing \(label)"); continue }
                let frame = control.frame
                // Save is correctly disabled while the owned editor is empty.
                let enabled = label == "Save" || control.isEnabled
                // The native OS globe has an enlarged 68pt AX frame extending
                // 3.4pt below the screen; its glyph and central target are fully
                // visible. Our own controls must still fit their whole frames.
                let visibleTarget: CGRect
                if label == "Globe" && !usesCustomGlobe {
                    visibleTarget = CGRect(x: frame.midX - 22, y: frame.midY - 22, width: 44, height: 44)
                } else {
                    visibleTarget = frame
                }
                if frame.width <= 0 || frame.height <= 0 || !frame.contains(visibleTarget) || !window.contains(visibleTarget) || !control.isHittable || !enabled {
                    layoutFailures.append("\(name): \(label) is clipped/unreachable; frame \(frame), window \(window)")
                }
            }
            let headerElements = [sayso.staticTexts["SAYSO"].firstMatch,
                                  sayso.staticTexts["keyboardPreview"], sayso.buttons["keyboardInsertButton"]]
            if let keyboardTop = headerElements.filter({ $0.exists }).map({ $0.frame.minY }).min() {
                let navigation = sayso.navigationBars["Edit text"]
                let editorTop = max(window.minY, navigation.exists ? navigation.frame.maxY : window.minY)
                let unobscuredArea = CGRect(x: window.minX, y: editorTop, width: window.width,
                                            height: max(0, keyboardTop - editorTop))
                let visibleEditor = editor.frame.intersection(unobscuredArea)
                let geometry = "Editor: \(editor.frame); navigation bottom: \(editorTop); keyboard header top: \(keyboardTop); visible editor: \(visibleEditor)"
                let attachment = XCTAttachment(string: geometry)
                attachment.name = "Keyboard-Landscape-\(name)-Editor-Geometry"
                attachment.lifetime = .keepAlways
                add(attachment)
                if !editor.isHittable || visibleEditor.isNull || visibleEditor.width <= 0 || visibleEditor.height < 44 {
                    layoutFailures.append("\(name): less than one usable line and margin above the keyboard. \(geometry)")
                }
            } else {
                layoutFailures.append("\(name): no custom keyboard header is available to measure editor visibility")
            }
        }
        try require(layoutFailures.isEmpty, layoutFailures.joined(separator: " | "), app: sayso)

        for (index, pair) in orientations.enumerated() {
            let (name, orientation) = pair
            if index > 0 {
                try closeOwnedSaysoEditor()
                XCUIDevice.shared.orientation = .portrait
                try publishLandscapePreview()
                editor = try prepareLandscapeEditor()
            }
            try rotate(orientation)
            let insert = sayso.buttons["keyboardInsertButton"]
            try require(waitFor(insert, predicate: "enabled == true AND label == 'Insert'", timeout: 5),
                        "The landscape keyboard did not retain a Ready publication.", app: sayso)
            XCTAssertEqual(sayso.staticTexts["keyboardPreview"].label, expectedText)
            try expectValue("", in: editor, app: sayso)
            sayso.buttons["keyboardKey-q"].tap()
            try expectValue("q", in: editor, app: sayso)
            sayso.buttons["keyboardSpaceButton"].tap()
            try expectValue("q ", in: editor, app: sayso)
            sayso.buttons["keyboardDeleteButton"].tap()
            try expectValue("q", in: editor, app: sayso)
            sayso.buttons["keyboardReturnButton"].tap()
            try expectValue("q\n", in: editor, app: sayso)
            sayso.buttons["keyboardDeleteButton"].tap()
            sayso.buttons["keyboardDeleteButton"].tap()
            try expectValue("", in: editor, app: sayso)
            XCTAssertTrue(insert.isEnabled, "Ordinary typing must not consume the publication.")
            insert.tap()
            try expectValue(expectedText, in: editor, app: sayso)
            try require(waitFor(insert, predicate: "enabled == false AND label == 'Inserted'", timeout: 5),
                        "Exact insertion was not marked consumed.", app: sayso)
            try require(sayso.buttons["saveEditButton"].isEnabled && sayso.buttons["saveEditButton"].isHittable,
                        "The host editor's Save action is unusable after insertion.", app: sayso)
            diagnose("Keyboard-Landscape-\(name)-Exactly-Inserted", app: sayso)
            try switchToSystemKeyboard(in: sayso)
            try expectValue(expectedText, in: editor, app: sayso)
        }
        try cleanupControlFixture()
    }

    private func publishLandscapePreview() throws {
        let publish = sayso.buttons["sendToKeyboardButton"]
        try revealResultControl(publish)
        publish.tap()
        let ready = sayso.alerts["Ready in your keyboard"]
        try require(ready.waitForExistence(timeout: 5), "The preview was not published to the real keyboard App Group.", app: sayso)
        ownsSharedFixture = true
        ready.buttons["OK"].tap()
    }

    private func prepareLandscapeEditor() throws -> XCUIElement {
        let edit = sayso.buttons["editButton"]
        try revealResultControl(edit)
        edit.tap()
        let editor = sayso.textViews["editText"]
        try require(editor.waitForExistence(timeout: 5), "Sayso's isolated editor did not open.", app: sayso)
        ownsSaysoEditor = true
        editor.tap()
        try dismissKeyboardIntroduction(in: sayso)
        if !hostInputModeButtonBecameReachable(in: sayso) {
            // Observed on iOS27: the editor can be Keyboard Focused while the
            // entire native keyboard remains below the window. Reopen this
            // unsaved synthetic editor once to establish a fresh responder.
            diagnose("Keyboard-Editor-Focused-Without-Visible-Keyboard", app: sayso)
            try closeOwnedSaysoEditor()
            try revealResultControl(edit)
            edit.tap()
            try require(editor.waitForExistence(timeout: 5), "The isolated editor did not reopen.", app: sayso)
            ownsSaysoEditor = true
            editor.tap()
            try dismissKeyboardIntroduction(in: sayso)
        }
        try waitForHostInputModeButton()
        try switchToSystemKeyboard(in: sayso)
        editor.press(forDuration: 1)
        let selectAll = sayso.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Select All")).firstMatch
        // At system AX XXXL the observed native menu exposes only Paste on
        // its first page. Follow its actual Next Page button; do not change
        // the source or bypass the selection/deletion assertions below.
        for page in 0..<4 {
            if selectAll.waitForExistence(timeout: 1) && selectAll.isHittable { break }
            let nextPage = sayso.buttons["Next Page"]
            let hasVisibleEditMenu = sayso.menuItems.allElementsBoundByIndex.contains { $0.isHittable }
            guard hasVisibleEditMenu, nextPage.exists && nextPage.isHittable else { break }
            diagnose("Keyboard-Editor-Selection-Menu-Page-\(page + 1)", app: sayso)
            nextPage.tap()
        }
        try require(selectAll.waitForExistence(timeout: 5) && selectAll.isHittable,
                    "The native editor did not expose Select All for the synthetic preview.", app: sayso)
        selectAll.tap()
        let delete = sayso.keyboards.keys["delete"]
        try require(delete.waitForExistence(timeout: 5) && delete.isHittable, "The system Delete key is not reachable.", app: sayso)
        delete.tap()
        try expectValue("", in: editor, app: sayso)
        try selectSaysoKeyboard(in: sayso)
        let insert = sayso.buttons["keyboardInsertButton"]
        try require(insert.waitForExistence(timeout: 15) && waitFor(insert, predicate: "enabled == true AND label == 'Insert'", timeout: 5),
                    "Sayso's actual keyboard did not become Ready in its own editor.", app: sayso)
        return editor
    }

    private func revealResultControl(_ control: XCUIElement) throws {
        let scroll = sayso.scrollViews["transcriptScrollView"]
        try require(scroll.waitForExistence(timeout: 5), "The result scroll view is unavailable.", app: sayso)
        for _ in 0..<20 {
            let viewport = scroll.frame.intersection(sayso.windows.firstMatch.frame).insetBy(dx: 2, dy: 2)
            if control.exists && viewport.contains(control.frame) && control.isHittable { break }
            let above = control.exists && control.frame.minY < viewport.minY
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.35 : 0.70))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.60 : 0.45)))
        }
        let viewport = scroll.frame.intersection(sayso.windows.firstMatch.frame).insetBy(dx: 2, dy: 2)
        try require(control.exists && viewport.contains(control.frame) && control.isEnabled && control.isHittable,
                    "The complete result action \(control.identifier) is not reachable.", app: sayso)
    }

    private func closeOwnedSaysoEditor() throws {
        guard ownsSaysoEditor else { return }
        sayso.activate()
        let editor = sayso.textViews["editText"]
        try require(editor.waitForExistence(timeout: 5), "The owned editor is unavailable during cleanup.", app: sayso)
        // Cancel must not depend on a functioning software keyboard. The
        // cleanup's separate final stage restores English after shared-text
        // and Full Access cleanup, even if keyboard presentation failed here.
        let cancel = sayso.navigationBars["Edit text"].buttons["Cancel"]
        try require(cancel.exists && cancel.isHittable, "The isolated editor cannot be cancelled.", app: sayso)
        cancel.tap()
        try require(editor.waitForNonExistence(timeout: 5), "The isolated editor did not close after Cancel.", app: sayso)
        ownsSaysoEditor = false
    }

    private func waitForHostInputModeButton() throws {
        try require(hostInputModeButtonBecameReachable(in: sayso),
                    "The host keyboard's input-mode control did not become reachable.", app: sayso)
    }

    private func hostInputModeButtonBecameReachable(in host: XCUIApplication) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let globe = self.inputModeButton(in: host)
            return globe.exists && globe.isHittable
        }, object: host)
        return XCTWaiter.wait(for: [ready], timeout: 5) == .completed
    }

    /// Verifies the real Full Access keyboard write and host consumption. The
    /// scripted source owns no audio background session, so foreground resumption
    /// is deliberate; this does not claim continuous background execution/audio.
    func testKeyboardStopThenExactInsertionWithFullAccessOn() throws {
        let search = try prepareControlKeyboard()
        let expectedText = try startScriptedCrossAppFixture()
        try returnToRecordingKeyboard(search)
        diagnose("Keyboard-Stop-Ready-Full-Access-On", app: settings)
        settings.buttons["keyboardInsertButton"].tap()

        // No app Stop/Live Activity action is used. Returning to the foreground
        // lets the no-audio fixture process only the keyboard's pending command.
        sayso.activate()
        let result = sayso.staticTexts["resultText"]
        try require(result.waitForExistence(timeout: 10),
                    "The host did not consume the keyboard's Stop command after foreground resumption.", app: sayso)
        XCTAssertEqual(result.label, expectedText, "Keyboard Stop must retain the complete scripted source.")
        let ready = sayso.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ready in the Sayso keyboard")).firstMatch
        try require(ready.waitForExistence(timeout: 5), "Stopped text was not prepared for keyboard insertion.", app: sayso)
        XCTAssertFalse(sayso.alerts["Couldn’t complete dictation"].exists)
        diagnose("Keyboard-Stop-Consumed-After-Foreground-Resume", app: sayso)

        try returnToPreparedSearch(search)
        let insert = settings.buttons["keyboardInsertButton"]
        try require(waitFor(insert, predicate: "enabled == true AND label == 'Insert'", timeout: 5),
                    "The keyboard did not receive the result of its Stop command.", app: settings)
        XCTAssertEqual(settings.staticTexts["keyboardPreview"].label, expectedText)
        XCTAssertFalse(settings.buttons["keyboardDiscardButton"].exists)
        XCTAssertEqual(contents(of: search), "", "Finishing a recording must not insert its result automatically.")
        diagnose("Keyboard-Stopped-Result-Ready", app: settings)
        insert.tap()
        try expectValue(expectedText, in: search)
        try require(waitFor(insert, predicate: "enabled == false AND label == 'Inserted'", timeout: 5),
                    "The stopped recording was not marked as consumed after exact insertion.", app: settings)
        diagnose("Keyboard-Stopped-Result-Inserted", app: settings)
        try cleanupControlFixture()
    }

    /// Discard must cross the real extension boundary and remove the synthetic
    /// background checkpoint. Foreground resume is intentional for the audio-free stub.
    func testKeyboardDiscardRemovesRecordingAndHandoffWithFullAccessOn() throws {
        let search = try prepareControlKeyboard()
        _ = try startScriptedCrossAppFixture()
        try returnToRecordingKeyboard(search)
        diagnose("Keyboard-Discard-Ready-Full-Access-On", app: settings)
        settings.buttons["keyboardDiscardButton"].tap()

        sayso.activate()
        let record = sayso.buttons["recordButton"]
        try require(waitFor(record, predicate: "enabled == true AND label == 'Start recording'", timeout: 10),
                    "The host did not consume keyboard Discard after foreground resumption.", app: sayso)
        XCTAssertFalse(sayso.staticTexts["liveTranscript"].exists)
        XCTAssertFalse(sayso.staticTexts["resultText"].exists)
        XCTAssertFalse(sayso.alerts["Couldn’t complete dictation"].exists)
        sayso.buttons["historyButton"].tap()
        let empty = sayso.descendants(matching: .any)["emptyHistory"].firstMatch
        try require(empty.waitForExistence(timeout: 5),
                    "Keyboard Discard left the current synthetic recording in history.", app: sayso)
        diagnose("Keyboard-Discard-Empty-History", app: sayso)
        sayso.navigationBars.buttons["Done"].tap()

        try returnToPreparedSearch(search)
        let insert = settings.buttons["keyboardInsertButton"]
        try require(waitFor(insert, predicate: "enabled == false AND label == 'Insert'", timeout: 5),
                    "Discarded recording remained insertable or its session remained active.", app: settings)
        try require(waitFor(settings.staticTexts["keyboardPreview"], predicate: "label == %@",
                            arguments: ["Your words, ready here."], timeout: 5),
                    "The keyboard did not return to its ordinary empty state after Discard.", app: settings)
        XCTAssertFalse(settings.buttons["keyboardDiscardButton"].exists)
        XCTAssertEqual(contents(of: search), "", "Discard must never insert or publish the recording.")
        diagnose("Keyboard-Discard-No-Shared-Result", app: settings)
        try cleanupControlFixture()
    }

    /// Real external host and extension commands, with four fresh audio-free
    /// sessions. Foreground resumption processes the command; this does not
    /// claim continuous background execution, microphone capture, or model use.
    /// Safari's address stays empty: never type, insert, press Return, or search.
    func testKeyboardStopAndDiscardInSafariBothLandscapeOrientations() throws {
        usesControlFixture = true
        restoresLandscapeEnvironment = true
        needsFullAccessRestoration = true
        landscapeAppearanceAtStart = XCUIDevice.shared.appearance
        XCUIDevice.shared.orientation = .portrait
        settings.launch()
        try enableSayso(fullAccess: true)

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safariControlHost = safari
        safari.launch()
        let orientations: [(String, UIDeviceOrientation)] = [
            ("Left", .landscapeLeft), ("Right", .landscapeRight)
        ]
        for (orientationName, orientation) in orientations {
            for shouldStop in [true, false] {
                let command = shouldStop ? "Stop" : "Discard"
                let captureName = "Safari-Landscape-\(orientationName)-\(command)"
                XCUIDevice.shared.orientation = orientation
                safari.activate()
                try waitForSafariLandscape(safari)
                // Prewarm the actual extension before the fresh recording so
                // cold setup does not consume the fixture's finite OS lease.
                let address = try prepareSafariKeyboard(safari)
                diagnose("\(captureName)-Prewarmed", app: safari)
                XCUIDevice.shared.orientation = .portrait
                let expectedText = try startScriptedCrossAppFixture()
                XCUIDevice.shared.orientation = orientation
                safari.activate()
                try waitForSafariLandscape(safari)
                try returnToSafariKeyboard(safari, address: address)

                let stop = safari.buttons["keyboardInsertButton"]
                let discard = safari.buttons["keyboardDiscardButton"]
                try require(waitFor(stop, predicate: "enabled == true AND label == 'Stop'", timeout: 5),
                            "The fresh Safari recording did not expose Stop with Full Access on.", app: safari)
                diagnose("\(captureName)-Recording-Controls", app: safari)
                try requireSafariControlGeometry(safari, address: address)
                XCTAssertEqual(contents(of: address), "", "Recording must never populate Safari's address.")
                (shouldStop ? stop : discard).tap()

                // Only the real keyboard sends Stop/Discard. The scripted
                // source has no audio background session, so resume explicitly.
                sayso.activate()
                if shouldStop {
                    let result = sayso.staticTexts["resultText"]
                    try require(result.waitForExistence(timeout: 10),
                                "Safari keyboard Stop was not consumed after foreground resumption.", app: sayso)
                    XCTAssertEqual(result.label, expectedText, "Keyboard Stop must retain the complete source.")
                    let ready = sayso.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ready in the Sayso keyboard")).firstMatch
                    try require(ready.waitForExistence(timeout: 5), "The stopped source was not shared with the keyboard.", app: sayso)
                } else {
                    let record = sayso.buttons["recordButton"]
                    try require(waitFor(record, predicate: "enabled == true AND label == 'Start recording'", timeout: 10),
                                "Safari keyboard Discard was not consumed after foreground resumption.", app: sayso)
                    XCTAssertFalse(sayso.staticTexts["liveTranscript"].exists)
                    XCTAssertFalse(sayso.staticTexts["resultText"].exists)
                    sayso.buttons["historyButton"].tap()
                    try require(sayso.descendants(matching: .any)["emptyHistory"].firstMatch.waitForExistence(timeout: 5),
                                "Safari keyboard Discard retained the fresh recording in history.", app: sayso)
                    diagnose("\(captureName)-Empty-History", app: sayso)
                    sayso.navigationBars.buttons["Done"].tap()
                }
                XCTAssertFalse(sayso.alerts["Couldn’t complete dictation"].exists)
                diagnose("\(captureName)-Consumed-After-Foreground-Resume", app: sayso)

                safari.activate()
                try waitForSafariLandscape(safari)
                try returnToSafariKeyboard(safari, address: address)
                let predicate = shouldStop ? "enabled == true AND label == 'Insert'" : "enabled == false AND label == 'Insert'"
                try require(waitFor(stop, predicate: predicate, timeout: 5),
                            "Safari keyboard did not settle after \(command).", app: safari)
                let expectedPreview = shouldStop ? expectedText : "Your words, ready here."
                try require(waitFor(safari.staticTexts["keyboardPreview"], predicate: "label == %@",
                                    arguments: [expectedPreview], timeout: 5),
                            "Safari keyboard's \(command) outcome did not match the complete expected text/state.", app: safari)
                XCTAssertFalse(discard.exists)
                XCTAssertEqual(contents(of: address), "", "Stop/Discard must not insert or submit text in Safari.")
                diagnose("\(captureName)-Settled-Without-Insertion", app: safari)
                try switchToSystemKeyboard(in: safari)
                XCTAssertEqual(contents(of: address), "", "Switching to English must preserve the empty address.")
            }
        }
        try cleanupControlFixture()
        XCUIDevice.shared.press(.home)
    }

    private func waitForSafariLandscape(_ safari: XCUIApplication) throws {
        let window = safari.windows.firstMatch
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.exists && window.frame.width > window.frame.height
        }, object: window)
        try require(XCTWaiter.wait(for: [expectation], timeout: 5) == .completed,
                    "Safari did not reach a native landscape window.", app: safari)
    }

    private func prepareSafariKeyboard(_ safari: XCUIApplication) throws -> XCUIElement {
        // Both native discovery captures expose this exact empty address field.
        // A changed focused selector or unrelated onboarding is a boundary to
        // capture and inspect, not a reason to guess another Safari workflow.
        let address = safari.textFields["TabBarItemTitleContainer"]
        try require(address.waitForExistence(timeout: 5) && address.label == "Address" && address.isHittable,
                    "Safari's observed native Address affordance is unavailable.", app: safari)
        try require(contents(of: address).isEmpty, "Safari's address is not empty; this probe must not change existing text.", app: safari)
        address.tap()
        try require(address.waitForExistence(timeout: 5) && address.label == "Address",
                    "Safari changed its focused address selector. Inspect the boundary before adding any interaction.", app: safari)
        try require(hostInputModeButtonBecameReachable(in: safari),
                    "Safari's address editor did not expose a visible native input-mode control.", app: safari)
        try selectSaysoKeyboard(in: safari)
        try require(safari.buttons["keyboardInsertButton"].waitForExistence(timeout: 15),
                    "Sayso's keyboard did not prewarm in Safari before recording.", app: safari)
        XCTAssertEqual(contents(of: address), "")
        return address
    }

    private func returnToSafariKeyboard(_ safari: XCUIApplication, address: XCUIElement) throws {
        try require(address.waitForExistence(timeout: 5) && address.label == "Address",
                    "The previously observed Safari address editor did not remain available.", app: safari)
        let insert = safari.buttons["keyboardInsertButton"]
        // Activation/rotation can precede the retained extension's AX tree.
        // Give that native view time to return before touching the address.
        if !insert.waitForExistence(timeout: 5) {
            diagnose("Safari-Retained-Keyboard-Not-Yet-Visible", app: safari)
            let globe = inputModeButton(in: safari)
            if !(globe.exists && globe.isHittable) {
                // The captured toolbar Address can be Keyboard Focused while
                // TabBarItemTitleContainer is its separate visible proxy. A
                // second tap then opens Paste/Paste and Search, without
                // restoring the keyboard. Read the public native AX snapshot
                // instead of treating a missing extension as lost focus.
                let addressAlreadyFocused = safari.debugDescription.split(separator: "\n").contains {
                    $0.contains("TextField,") && $0.contains("label: 'Address'") && $0.contains("Keyboard Focused")
                }
                try require(!addressAlreadyFocused,
                            "Safari retained Address keyboard focus but no software keyboard returned. Refusing to retap the focused proxy or open search/edit menus.", app: safari)
                try require(address.isHittable, "Safari's empty address editor is not reachable.", app: safari)
                address.tap()
                try require(hostInputModeButtonBecameReachable(in: safari),
                            "Refocusing Safari's empty address did not expose a native input-mode control.", app: safari)
            }
            try selectSaysoKeyboard(in: safari)
        }
        try require(insert.waitForExistence(timeout: 15),
                    "The prewarmed Sayso keyboard did not return to Safari.", app: safari)
        XCTAssertEqual(contents(of: address), "")
    }

    private func requireSafariControlGeometry(_ safari: XCUIApplication, address: XCUIElement) throws {
        let window = safari.windows.firstMatch.frame
        var failures: [String] = []
        for identifier in ["keyboardInsertButton", "keyboardDiscardButton", "keyboardKey-q", "keyboardDeleteButton", "keyboardReturnButton"] {
            let control = safari.buttons[identifier]
            guard control.exists else { failures.append("Missing \(identifier)"); continue }
            let frame = control.frame
            let isRecordingAction = identifier == "keyboardInsertButton" || identifier == "keyboardDiscardButton"
            if frame.width <= 0 || frame.height <= 0 || !window.contains(frame) || !control.isEnabled || !control.isHittable ||
                (isRecordingAction && (frame.width < 44 || frame.height < 44)) {
                failures.append("Clipped/unreachable \(identifier): \(frame), window \(window)")
            }
        }
        let customGlobe = safari.buttons["keyboardNextButton"]
        let usesCustomGlobe = customGlobe.exists && customGlobe.isHittable
        let globe = usesCustomGlobe ? customGlobe : inputModeButton(in: safari)
        if globe.exists {
            let frame = globe.frame
            let target = usesCustomGlobe ? frame : CGRect(x: frame.midX - 22, y: frame.midY - 22, width: 44, height: 44)
            if frame.width <= 0 || frame.height <= 0 || !frame.contains(target) || !window.contains(target) || !globe.isEnabled || !globe.isHittable {
                failures.append("The native input-mode target is not fully reachable: \(frame)")
            }
        } else { failures.append("No native input-mode control") }
        let addressFrame = address.frame
        let headerTop = min(safari.staticTexts["keyboardPreview"].frame.minY,
                            safari.buttons["keyboardInsertButton"].frame.minY)
        if !address.isHittable || !window.contains(addressFrame) || addressFrame.width <= 0 || addressFrame.height < 44 || addressFrame.maxY > headerTop {
            failures.append("Safari's address is not wholly usable above the keyboard: \(addressFrame), header top \(headerTop)")
        }
        try require(failures.isEmpty, failures.joined(separator: " | "), app: safari)
    }

    private func prepareControlKeyboard() throws -> XCUIElement {
        usesControlFixture = true
        settings.launch()
        try enableSayso(fullAccess: true)
        try returnToSettingsRoot()
        let search = try openSettingsSearch()
        try clearSearch(search)
        ownsSettingsSearch = true
        try selectSaysoKeyboard()
        // Prewarm before recording: navigation/extension cold startup must not
        // consume the finite background execution of an audio-free fixture.
        try require(settings.buttons["keyboardInsertButton"].waitForExistence(timeout: 15),
                    "The Sayso extension did not appear before starting the control fixture.", app: settings)
        return search
    }

    private func startScriptedCrossAppFixture() throws -> String {
        sayso.launchArguments = ["--uitesting", "--scripted-speech"]
        sayso.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        launchedScriptedFixture = true
        sayso.launch()
        let start = sayso.buttons["keyboardRecordButton"]
        try require(start.waitForExistence(timeout: 10) && start.isEnabled && start.isHittable,
                    "The explicit cross-app recording action is not reachable.", app: sayso)
        start.tap()
        let live = sayso.staticTexts["liveTranscript"]
        try require(live.waitForExistence(timeout: 10) && sayso.buttons["recordButton"].label == "Stop recording",
                    "The scripted cross-app recording did not start with a real Live Activity.", app: sayso)
        // Successful cross-app startup clears prior shared text and creates this
        // test's session. Cleanup may now remove only this synthetic handoff.
        ownsSharedFixture = true
        try require(waitFor(live, predicate: "label ENDSWITH %@", arguments: ["next project."], timeout: 10),
                    "The complete scripted utterance was not captured before switching apps.", app: sayso)
        let expectedText = live.label
        try require(!expectedText.isEmpty, "The scripted utterance must be nonempty.", app: sayso)
        return expectedText
    }

    private func returnToPreparedSearch(_ search: XCUIElement) throws {
        settings.activate()
        try require(search.waitForExistence(timeout: 5),
                    "The previously prepared Settings search was not retained.", app: settings)
        // Returning to an already focused field retains the real extension.
        // Tapping it again opens Settings' Paste/AutoFill editing menu.
        if !settings.buttons["keyboardInsertButton"].exists {
            try require(search.isHittable, "The prepared Settings search is not reachable.", app: settings)
            search.tap()
        }
        try selectSaysoKeyboard()
        try require(settings.buttons["keyboardInsertButton"].waitForExistence(timeout: 15),
                    "The Sayso keyboard did not return to the prepared Settings field.", app: settings)
    }

    private func returnToRecordingKeyboard(_ search: XCUIElement) throws {
        try returnToPreparedSearch(search)
        let stop = settings.buttons["keyboardInsertButton"]
        try require(waitFor(stop, predicate: "enabled == true AND label == 'Stop'", timeout: 5) && stop.isHittable,
                    "The real keyboard did not expose an enabled Stop control with Full Access on.", app: settings)
        let discard = settings.buttons["keyboardDiscardButton"]
        try require(discard.exists && discard.isEnabled && discard.isHittable,
                    "The real keyboard did not expose Discard with Full Access on.", app: settings)
        XCTAssertEqual(contents(of: search), "", "Switching to a recording keyboard must not insert text.")
    }

    private func cleanupControlFixture() throws {
        cleanupAttempted = true
        let previousContinuation = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousContinuation }
        var failures: [String] = []
        func attempt(_ name: String, _ action: () throws -> Void) {
            do { try action() }
            catch { failures.append("\(name): \(error)") }
        }
        attempt("Restore landscape probe environment") {
            guard restoresLandscapeEnvironment else { return }
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.appearance = landscapeAppearanceAtStart
            try require(XCUIDevice.shared.orientation == .portrait && XCUIDevice.shared.appearance == landscapeAppearanceAtStart,
                        "Portrait and the original appearance were not restored.", app: sayso)
        }
        attempt("Cancel the isolated editor") {
            if ownsSaysoEditor { try closeOwnedSaysoEditor() }
        }
        attempt("Leave the empty Safari address editor") {
            // No Safari text was entered and no tab was created or loaded.
            // Home safely ends the probe without guessing a new Cancel selector.
            if safariControlHost != nil { XCUIDevice.shared.press(.home) }
        }
        attempt("Stop any remaining synthetic recording") {
            if launchedScriptedFixture { try cancelScriptedFixtureIfNeeded() }
        }
        attempt("Clear only the shared synthetic fixture") {
            if ownsSharedFixture {
                try clearPublishedFixture()
                ownsSharedFixture = false
            }
        }
        attempt("Empty Settings search and restore the system keyboard") {
            guard ownsSettingsSearch else { return }
            settings.activate()
            try dismissPendingFullAccessConfirmation()
            // Activation can return before Settings republishes its AX tree.
            // This test owns the prepared search, so wait for that field and
            // clear it directly before closing search or navigating elsewhere.
            let search = settings.searchFields.firstMatch
            try require(search.waitForExistence(timeout: 5),
                        "The owned Settings search did not return for cleanup.", app: settings)
            try clearSearch(search)
            try switchToSystemKeyboard()
            closeSettingsSearchIfPresent()
            try require(settings.navigationBars["Settings"].waitForExistence(timeout: 5),
                        "Settings search did not close after its synthetic text was cleared.", app: settings)
            ownsSettingsSearch = false
        }
        attempt("Restore Full Access off") {
            guard needsFullAccessRestoration else { return }
            // Search is already cleared and its keyboard restored. Start a
            // fresh Settings process for permission cleanup: on iOS 26.5 at
            // AX XXXL, closing search left XCTest waiting 60 seconds for an
            // animation-complete notification before every later action.
            settings.launch()
            try dismissPendingFullAccessConfirmation()
            try enableSaysoWithFullAccessOff()
            needsFullAccessRestoration = false
        }
        attempt("Restore English input after the landscape probe") {
            guard restoresLandscapeEnvironment else { return }
            settings.activate()
            try returnToSettingsRoot()
            let search = try openSettingsSearch()
            let existingText = contents(of: search)
            // This restoration enters no text. If the system keyboard is
            // still hidden, close search before recording the failure; the
            // owned editor and shared publication have already been cleared.
            guard hostInputModeButtonBecameReachable(in: settings) else {
                closeSettingsSearchIfPresent()
                try require(false, "The system keyboard remained unavailable while restoring English input.", app: settings)
                return
            }
            try switchToSystemKeyboard()
            XCTAssertEqual(contents(of: search), existingText,
                           "Restoring English input must not modify Settings search.")
            closeSettingsSearchIfPresent()
            try require(settings.navigationBars["Settings"].waitForExistence(timeout: 5),
                        "Settings search did not close after restoring English input.", app: settings)
        }
        if !failures.isEmpty {
            let message = "Keyboard fixture cleanup could not complete: " + failures.joined(separator: " | ")
            XCTFail(message)
            throw NavigationFailure.unavailable(message)
        }
    }

    private func cancelScriptedFixtureIfNeeded() throws {
        sayso.activate()
        let error = sayso.alerts["Couldn’t complete dictation"]
        if error.exists && error.buttons["OK"].isHittable { error.buttons["OK"].tap() }
        for _ in 0..<3 {
            let done = sayso.navigationBars.buttons["Done"].firstMatch
            guard done.exists && done.isHittable else { break }
            done.tap()
        }
        let record = sayso.buttons["recordButton"]
        try require(record.waitForExistence(timeout: 5), "Cannot reach the synthetic recorder during cleanup.", app: sayso)
        if record.label == "Stop recording" {
            let discard = sayso.buttons["Discard recording"].firstMatch
            try require(discard.exists && discard.isHittable, "Cannot discard the active synthetic recording during cleanup.", app: sayso)
            discard.tap()
            let sheet = sayso.sheets.firstMatch
            try require(sheet.waitForExistence(timeout: 3) && sheet.buttons["Discard recording"].isHittable,
                        "The synthetic recording's discard confirmation did not appear.", app: sayso)
            sheet.buttons["Discard recording"].tap()
        } else {
            let cancel = sayso.buttons["Cancel"].firstMatch
            if cancel.exists && cancel.isEnabled && cancel.isHittable { cancel.tap() }
        }
        try require(waitFor(record, predicate: "enabled == true AND label == 'Start recording'", timeout: 10),
                    "The synthetic recording did not settle during cleanup.", app: sayso)
    }

    private func clearPublishedFixture() throws {
        sayso.activate()
        let settingsButton = sayso.buttons["settingsButton"]
        try require(settingsButton.waitForExistence(timeout: 5), "Cannot open Sayso Settings to clear the shared fixture.", app: sayso)
        settingsButton.tap()
        diagnose("Keyboard-Cleanup-Settings", app: sayso)
        let setup = sayso.buttons["Sayso keyboard"]
        try revealFormControl(setup, description: "Sayso keyboard setup")
        diagnose("Keyboard-Cleanup-Settings-Shortcuts", app: sayso)
        setup.tap()
        let clear = sayso.buttons["Clear shared text"]
        try revealFormControl(clear, description: "Clear shared text")
        diagnose("Keyboard-Clear-Shared-Text-Reachable", app: sayso)
        clear.tap()
        let confirmation = sayso.alerts["Shared text"]
        try require(confirmation.waitForExistence(timeout: 5) &&
                    confirmation.staticTexts["The text shared with your keyboard has been removed."].exists,
                    "The synthetic shared fixture was not cleared successfully.", app: sayso)
        diagnose("Keyboard-Shared-Fixture-Cleared", app: sayso)
        confirmation.buttons["OK"].tap()
    }

    private func revealFormControl(_ control: XCUIElement, description: String) throws {
        // SwiftUI Form is a collection view. Five whole-screen swipes were
        // insufficient for the long keyboard instructions at system AX XXXL.
        // Scroll the actual Form, then require the complete target below its
        // navigation bar before tapping; a hittable sliver is insufficient.
        let form = sayso.collectionViews.firstMatch
        try require(form.waitForExistence(timeout: 5), "No Form for \(description).", app: sayso)
        let navigation = sayso.navigationBars.firstMatch
        func viewport() -> CGRect {
            let frame = form.frame.intersection(sayso.windows.firstMatch.frame)
            let top = max(frame.minY, navigation.exists ? navigation.frame.maxY : frame.minY) + 6
            return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, frame.maxY - top - 6))
        }
        for _ in 0..<48 {
            if control.exists, viewport().contains(control.frame), control.isHittable { break }
            let above = control.exists && control.frame.minY < viewport().minY
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.35 : 0.80))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.65 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        try require(control.exists && viewport().contains(control.frame) && control.isEnabled && control.isHittable,
                    "Cannot fully reach \(description) after bounded Form scrolling.", app: sayso)
    }

    private func enableSaysoWithFullAccessOff() throws {
        try enableSayso(fullAccess: false)
    }

    private func enableSayso(fullAccess: Bool) throws {
        try returnToSettingsRoot()
        try tapRow("General")
        try require(settings.navigationBars["General"].waitForExistence(timeout: 5),
                    "The General settings page did not open.", app: settings)
        try tapRow("Keyboard")
        try require(settings.navigationBars["Keyboards"].waitForExistence(timeout: 5),
                    "The Keyboard settings page did not open after its navigation button was tapped.", app: settings)
        try tapRow("KEYBOARDS", alternatives: ["Keyboards"])
        if !row("Sayso").exists {
            // iOS 26.5 exposes this as AddNewKeyboard, with no ellipsis in its label.
            try tapRow("AddNewKeyboard", alternatives: ["Add New Keyboard", "Add New Keyboard…", "Add New Keyboard..."])
            try tapRow("Sayso")
            // Some OS releases present a language selection page before Done.
            let done = settings.navigationBars.buttons["Done"]
            if done.waitForExistence(timeout: 1) && done.isHittable { done.tap() }
        }
        try tapRow("Sayso")
        let access = settings.switches["Allow Full Access"]
        try require(access.waitForExistence(timeout: 5),
                    "Settings did not expose Sayso's Allow Full Access switch.", app: settings)
        if fullAccess { needsFullAccessRestoration = true }
        let desired = fullAccess ? "1" : "0"
        if access.value as? String != desired {
            // iOS 26.5 exposes a named row-sized switch containing the actual
            // toggle. Tapping the row's center hits its label instead of toggling.
            let nestedSwitch = access.switches.firstMatch
            let toggle = nestedSwitch.exists && nestedSwitch.isHittable ? nestedSwitch : access
            try require(toggle.isHittable, "The Full Access toggle is not reachable.", app: settings)
            toggle.tap()
            if fullAccess {
                let alert = settings.alerts.firstMatch
                if alert.waitForExistence(timeout: 3) {
                    let explanation = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Full Access")).firstMatch
                    let allow = alert.buttons["Allow"]
                    try require(explanation.exists && allow.exists && allow.isHittable,
                                "Unexpected Full Access confirmation requires inspection before continuing.", app: settings)
                    diagnose("Keyboard-Full-Access-Confirmation", app: settings)
                    allow.tap()
                }
            }
        }
        try require(waitFor(access, predicate: "value == %@", arguments: [desired], timeout: 5),
                    "Settings did not leave Full Access \(fullAccess ? "on" : "off") as requested.", app: settings)
        diagnose(fullAccess ? "Keyboard-Full-Access-On" : "Keyboard-Full-Access-Off", app: settings)
    }

    private func dismissPendingFullAccessConfirmation() throws {
        let alert = settings.alerts.firstMatch
        guard alert.exists else { return }
        let explanation = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Full Access")).firstMatch
        let decline = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don't Allow", "Don’t Allow", "Cancel"])).firstMatch
        try require(explanation.exists && decline.exists && decline.isHittable,
                    "An unexpected Settings alert prevents restoring Full Access off.", app: settings)
        decline.tap()
    }

    private func returnToSettingsRoot() throws {
        for _ in 0..<10 {
            closeSettingsSearchIfPresent()
            // General also has a descriptive PLACARD cell titled General. That
            // cell is not the root's General navigation row; require the root bar.
            if settings.navigationBars["Settings"].exists { return }
            let observedBack = settings.navigationBars.buttons["BackButton"]
            let back = observedBack.exists ? observedBack : settings.navigationBars.buttons.matching(NSPredicate(
                format: "label IN %@", ["Settings", "General", "Keyboard", "Keyboards", "Back"]
            )).firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
        }
        try require(false, "Cannot return to the Settings root through visible back controls.", app: settings)
    }

    private func closeSettingsSearchIfPresent() {
        guard settings.searchFields.firstMatch.exists else { return }
        let window = settings.windows.firstMatch
        guard window.exists else { return }
        let visibleFrame = window.frame
        let candidates = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "close"]))
        for close in candidates.allElementsBoundByIndex {
            guard close.exists else { continue }
            let frame = close.frame
            guard frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0,
                  visibleFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            // Observed on iOS 26.5 after foreground activation: this visible
            // close control has a valid frame but isHittable throws an XCTest
            // activation-point failure. Tap the actual element's center instead.
            close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
    }

    private func row(_ title: String) -> XCUIElement {
        settings.cells.containing(.staticText, identifier: title).firstMatch
    }

    private func tapRow(_ title: String, alternatives: [String] = []) throws {
        let names = [title] + alternatives
        for _ in 0..<20 {
            let window = settings.windows.firstMatch.frame
            let navigation = settings.navigationBars.firstMatch
            let top = max(window.minY, navigation.exists ? navigation.frame.maxY : window.minY) + 8
            var bottom = window.maxY - 48
            // iOS 27 puts search over the bottom of the Add Keyboard sheet.
            // XCTest can report covered table rows as hittable; keep the whole
            // row above that visible overlay and the software keyboard.
            for search in settings.searchFields.allElementsBoundByIndex {
                let frame = search.frame
                if frame.minY > window.midY && window.intersects(frame) {
                    bottom = min(bottom, frame.minY - 12)
                }
            }
            for keyboard in settings.keyboards.allElementsBoundByIndex {
                if window.intersects(keyboard.frame) { bottom = min(bottom, keyboard.frame.minY - 12) }
            }
            let viewport = CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top))
            var target: XCUIElement?
            for name in names {
                // iOS 27 exposes navigation as buttons inside collection-view
                // cells. Target the actionable button before its container.
                let candidates = [settings.buttons[name], row(name), settings.staticTexts[name]]
                if let element = candidates.first(where: { $0.exists && viewport.contains($0.frame) && $0.isHittable }) {
                    element.tap()
                    return
                }
                if target == nil { target = candidates.first(where: { $0.exists }) }
            }
            // Settings uses both tables and collections. The final table is
            // the foreground Add Keyboard sheet, above the underlying list.
            let table = settings.tables.allElementsBoundByIndex.last(where: { $0.isHittable })
            let collection = settings.collectionViews.firstMatch
            let scroll: XCUIElement
            if let table { scroll = table }
            else if collection.exists { scroll = collection }
            else { scroll = settings }
            let frame = scroll.frame.intersection(viewport)
            try require(frame.height > 80, "No visible Settings list viewport for '\(title)'.", app: settings)
            let above = target.map { $0.frame.minY < viewport.minY } ?? false
            let start = settings.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: frame.maxX - 20, dy: frame.minY + frame.height * (above ? 0.3 : 0.75)))
            let end = settings.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: frame.maxX - 20, dy: frame.minY + frame.height * (above ? 0.75 : 0.3)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        try require(false, "Settings row '\(title)' was not reachable.", app: settings)
    }

    private func openSettingsSearch() throws -> XCUIElement {
        let search = settings.searchFields.firstMatch
        if !search.exists {
            let button = settings.buttons["Search"]
            if button.exists && button.isHittable { button.tap() }
            else { settings.swipeDown() }
        }
        try require(search.waitForExistence(timeout: 5), "Settings did not expose a searchable text field.", app: settings)
        search.tap()
        try dismissKeyboardIntroduction()
        return search
    }

    private func dismissKeyboardIntroduction(in app: XCUIApplication? = nil) throws {
        let host = app ?? settings!
        // Observed on the dedicated iOS 26.5 simulator's first keyboard use.
        // This tutorial covers the keyboard although underlying keys still appear in AX.
        let introduction = host.otherElements["UIContinuousPathIntroductionView"]
        guard introduction.waitForExistence(timeout: 1) else { return }
        let explanation = introduction.staticTexts[
            "Speed up your typing by sliding your finger across the letters to compose a word."
        ]
        let next = introduction.buttons["Continue"]
        try require(explanation.exists && next.exists && next.isHittable,
                    "Unexpected keyboard onboarding requires inspection before continuing.", app: host)
        next.tap()
        try require(waitFor(introduction, predicate: "exists == false", timeout: 5),
                    "The keyboard introduction did not close.", app: host)
    }

    private func clearSearch(_ search: XCUIElement) throws {
        guard !contents(of: search).isEmpty else { return }
        let clear = search.buttons.matching(NSPredicate(format: "label IN %@", ["Clear text", "Clear Text", "Clear"])).firstMatch
        try require(clear.exists && clear.isHittable, "Settings search has no visible clear-text control.", app: settings)
        clear.tap()
        XCTAssertEqual(contents(of: search), "")
    }

    private func selectSaysoKeyboard(in app: XCUIApplication? = nil) throws {
        let host = app ?? settings!
        try dismissKeyboardIntroduction(in: host)
        if host.buttons["keyboardInsertButton"].exists { return }
        let globe = inputModeButton(in: host)
        try require(globe.waitForExistence(timeout: 5) && globe.isHittable,
                    "The system keyboard has no visible globe/input-mode control. It may be hidden by a connected hardware keyboard.", app: host)
        // The native value identifies the next target. Two AX picker selections
        // left English visible; an observed direct Next keyboard tap opened Sayso.
        if globe.label == "Next keyboard" && (globe.value as? String) == "Sayso" {
            globe.tap()
            return
        }
        globe.press(forDuration: 1)
        try tapInputMode(containing: "Sayso", in: host)
    }

    private func switchToSystemKeyboard(in app: XCUIApplication? = nil) throws {
        let host = app ?? settings!
        // iOS 26.5 supplies a bottom Next keyboard button and sets
        // needsInputModeSwitchKey=false, so the extension correctly hides its own.
        let customGlobe = host.buttons["keyboardNextButton"]
        let globe = customGlobe.exists && customGlobe.isHittable ? customGlobe : inputModeButton(in: host)
        try require(globe.exists && globe.isHittable, "No visible keyboard-switching control is available.", app: host)
        globe.press(forDuration: 1)
        try tapInputMode(containing: "English", in: host)
        try require(waitFor(host.buttons["keyboardInsertButton"], predicate: "exists == false", timeout: 5),
                    "Choosing English did not switch away from Sayso.", app: host)
    }

    private func inputModeButton(in app: XCUIApplication? = nil) -> XCUIElement {
        let host = app ?? settings!
        let systemGlobe = host.buttons["Next keyboard"]
        if systemGlobe.exists && systemGlobe.isHittable { return systemGlobe }
        let predicate = NSPredicate(format: "label IN %@",
                                    ["Next keyboard", "Next Keyboard", "Emoji", "Emoji keyboard", "International"])
        let button = host.buttons.matching(predicate).firstMatch
        if button.exists { return button }
        return host.keys.matching(predicate).firstMatch
    }

    private func tapInputMode(containing text: String, in app: XCUIApplication? = nil) throws {
        let host = app ?? settings!
        // Observed rows are English (US), English (UK), and Sayso, English.
        // Match a row prefix so English never selects Sayso's language subtitle.
        let menu = host.tables["InputSwitcherTable"]
        if menu.waitForExistence(timeout: 2) {
            let choice = menu.cells.matching(NSPredicate(format: "label BEGINSWITH[c] %@", text)).firstMatch
            try require(choice.exists && choice.isHittable, "The input-mode menu has no selectable '\(text)' row.", app: host)
            choice.tap()
            return
        }
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let button = host.buttons.matching(predicate).firstMatch
        let label = host.staticTexts.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 2) && button.isHittable { button.tap(); return }
        if label.exists && label.isHittable { label.tap(); return }
        try require(false, "The visible input-mode menu did not list '\(text)'.", app: host)
    }

    private func contents(of field: XCUIElement) -> String {
        let value = field.value as? String ?? ""
        return value == field.placeholderValue ? "" : value
    }

    private func expectValue(_ expected: String, in field: XCUIElement, app: XCUIApplication? = nil) throws {
        try require(waitFor(field, predicate: "value == %@", arguments: [expected], timeout: 5),
                    "The owned text field did not contain the exact expected text. Expected: \(expected); actual: \(contents(of: field))",
                    app: app ?? settings!)
    }

    private func waitFor(_ element: XCUIElement, predicate: String, arguments: [Any] = [], timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate, argumentArray: arguments), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func require(_ condition: Bool, _ message: String, app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else {
            diagnose("Keyboard-Navigation-Boundary", app: app)
            XCTFail(message, file: file, line: line)
            throw NavigationFailure.unavailable(message)
        }
    }

    private func diagnose(_ name: String, app: XCUIApplication) {
        // Capture the native surface without asking an inactive app for an image.
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let state = app.state
        let description = state == .runningForeground
            ? app.debugDescription
            : "Hierarchy unavailable: application is not in the foreground."
        let hierarchy = XCTAttachment(string: "Application state: \(state)\n\n" + description)
        hierarchy.name = "\(name)-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private enum NavigationFailure: Error { case unavailable(String) }
}
