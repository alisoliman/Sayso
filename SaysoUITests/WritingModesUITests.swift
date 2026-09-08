import XCTest

/// Checks mode authoring, persistence and native rewrite routing. Scripted
/// rewrites return the transcript; these tests do not assess model quality.
@MainActor
final class WritingModesUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNamedModePersistsEditsDiscardsCancelledDraftAndDeletesSelectedMode() throws {
        let app = launch()
        let title = "Meeting notes"
        let prompt = "Summarize this as three concise action items."
        addMode(title: title, prompt: prompt, in: app)
        XCTAssertTrue(app.buttons["modeButton"].label.contains(title))

        openModes(in: app)
        let id = try modeID(named: title, in: app)
        openEditor(id: id, in: app)
        let editor = app.textViews["rewritePromptEditor"]
        XCTAssertEqual(editor.value as? String, prompt)
        editor.tap()
        editor.typeText(" This draft must be discarded.")
        XCTAssertNotEqual(editor.value as? String, prompt)
        app.buttons["cancelModeButton"].tap()
        openEditor(id: id, in: app)
        XCTAssertEqual(editor.value as? String, prompt, "Cancel must preserve the saved prompt.")

        let renamedTitle = "Project notes"
        let name = app.textFields["modeNameField"]
        replaceText(in: name, with: renamedTitle, app: app)
        editor.tap()
        editor.typeText(" Include an owner for each action.")
        let revisedPrompt = try XCTUnwrap(editor.value as? String)
        XCTAssertNotEqual(revisedPrompt, prompt)
        app.buttons["saveModeButton"].tap()
        XCTAssertTrue(app.navigationBars["Modes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode-\(id)"].label.contains(renamedTitle))

        app.terminate()
        app.launch()
        let modeButton = app.buttons["modeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 10))
        XCTAssertTrue(modeButton.label.contains(renamedTitle), "The selected mode and its renamed title must survive relaunch.")
        app.buttons["settingsButton"].tap()
        let settingsModes = app.buttons["writingModesSettingsButton"]
        reveal(settingsModes, in: app)
        settingsModes.tap()
        XCTAssertTrue(app.navigationBars["Writing modes"].waitForExistence(timeout: 5))
        capture("Writing-Modes-Settings", app: app)
        openEditor(id: id, in: app)
        XCTAssertEqual(name.value as? String, renamedTitle)
        XCTAssertEqual(editor.value as? String, revisedPrompt, "The edited prompt must survive relaunch and be shared with Settings.")
        capture("Writing-Mode-Saved-Editor", app: app)

        let delete = app.buttons["deleteModeButton"]
        reveal(delete, in: app)
        delete.tap()
        let confirm = app.buttons["confirmDeleteModeButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture("Writing-Mode-Delete-Confirmation", app: app)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Writing modes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["edit-mode-\(id)"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(modeButton.waitForExistence(timeout: 10))
        XCTAssertTrue(modeButton.label.contains("Original"), "Deleting the selected mode must persist the Original fallback.")
        openModes(in: app)
        XCTAssertFalse(app.buttons["mode-\(id)"].exists)
    }

    func testBuiltInPromptCanBeCustomizedAndRestoredWithoutChangingOriginal() throws {
        let app = launch()
        openModes(in: app)
        XCTAssertTrue(app.buttons["mode-transcript"].exists)
        XCTAssertFalse(app.buttons["edit-mode-transcript"].exists, "Original must always preserve the transcript.")
        openEditor(id: "clean", in: app)
        XCTAssertTrue(app.navigationBars["Clean prompt"].exists)
        XCTAssertFalse(app.textFields["modeNameField"].exists)
        let editor = app.textViews["rewritePromptEditor"]
        let defaultPrompt = try XCTUnwrap(editor.value as? String)
        XCTAssertFalse(defaultPrompt.isEmpty)
        XCTAssertTrue(app.buttons["saveModeButton"].isEnabled)
        editor.tap()
        editor.typeText(" Keep each sentence under twelve words.")
        let savedPrompt = try XCTUnwrap(editor.value as? String)
        XCTAssertNotEqual(savedPrompt, defaultPrompt)
        capture("Writing-Mode-Customized-Preset", app: app)
        app.buttons["saveModeButton"].tap()
        XCTAssertTrue(app.navigationBars["Modes"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        openModes(in: app)
        openEditor(id: "clean", in: app)
        XCTAssertEqual(editor.value as? String, savedPrompt)
        let reset = app.buttons["resetModePromptButton"]
        reveal(reset, in: app)
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        XCTAssertEqual(editor.value as? String, defaultPrompt)
        XCTAssertFalse(reset.isEnabled)
        app.buttons["cancelModeButton"].tap()
        openEditor(id: "clean", in: app)
        XCTAssertEqual(editor.value as? String, savedPrompt, "Restoring the default must remain a draft until Save.")
        reveal(reset, in: app)
        reset.tap()
        app.buttons["saveModeButton"].tap()

        app.terminate()
        app.launch()
        openModes(in: app)
        openEditor(id: "clean", in: app)
        XCTAssertEqual(editor.value as? String, defaultPrompt, "Saving the restored prompt must persist the original default.")
    }

    func testNewModeIsAvailableForHomeAndSavedHistoryRewrites() throws {
        let app = launch(previewResult: true)
        let result = app.staticTexts["resultText"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        // Rewrites use the current text so that a user's edits are preserved.
        // The scripted transformer returns that text without changing it.
        let refined = result.label

        let title = "Quick reply"
        addMode(title: title, prompt: "Write a brief, friendly reply.", in: app)
        openModes(in: app)
        let id = try modeID(named: title, in: app)
        app.navigationBars["Modes"].buttons["Done"].tap()
        app.buttons["rewriteButton"].tap()
        let homeRewrite = app.buttons["rewrite-\(id)"]
        XCTAssertTrue(homeRewrite.waitForExistence(timeout: 5))
        XCTAssertTrue(homeRewrite.isEnabled)
        XCTAssertTrue(homeRewrite.label.contains(title))
        XCTAssertTrue(app.buttons["rewrite-transcript"].exists)
        capture("Writing-Mode-Home-Rewrite-Menu", app: app)
        homeRewrite.tap()
        waitForRewrite(in: app)
        expectLabel(refined, on: result)

        app.buttons["historyButton"].tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", refined)).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "The saved mode name must reflect the named rewrite selected on Home.")
        saved.tap()
        let historyRewrite = app.buttons["historyRewriteButton"]
        reveal(historyRewrite, in: app)
        historyRewrite.tap()
        let namedRewrite = app.buttons["history-rewrite-\(id)"]
        XCTAssertTrue(namedRewrite.waitForExistence(timeout: 5))
        XCTAssertTrue(namedRewrite.isEnabled)
        XCTAssertTrue(namedRewrite.label.contains(title))
        XCTAssertTrue(app.buttons["history-rewrite-transcript"].exists)
        capture("Writing-Mode-History-Rewrite-Menu", app: app)
        namedRewrite.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForNonExistence(timeout: 5))
        waitForRewrite(in: app)
        expectLabel(refined, on: result)
        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "A saved-history rewrite must retain the selected named mode.")
    }

    private func launch(previewResult: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--scripted-speech"] + (previewResult ? ["--preview-result"] : [])
        app.launchEnvironment["TEST_STORAGE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["modeButton"].waitForExistence(timeout: 10))
        return app
    }

    private func openModes(in app: XCUIApplication) {
        let modeButton = app.buttons["modeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 10))
        modeButton.tap()
        XCTAssertTrue(app.navigationBars["Modes"].waitForExistence(timeout: 5))
    }

    private func addMode(title: String, prompt: String, in app: XCUIApplication) {
        openModes(in: app)
        let add = app.buttons["addModeButton"]
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.navigationBars["New mode"].waitForExistence(timeout: 5))
        let save = app.buttons["saveModeButton"]
        XCTAssertFalse(save.isEnabled)
        let name = app.textFields["modeNameField"]
        name.tap()
        name.typeText(title)
        XCTAssertFalse(save.isEnabled, "A new mode needs both a name and a prompt.")
        let editor = app.textViews["rewritePromptEditor"]
        editor.tap()
        editor.typeText(prompt)
        XCTAssertTrue(save.isEnabled)
        capture("Writing-Mode-New-Ready-To-Save", app: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Modes"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modeButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modeButton"].label.contains(title))
    }

    private func modeID(named title: String, in app: XCUIApplication) throws -> String {
        let mode = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "mode-", title)).firstMatch
        reveal(mode, in: app)
        let id = String(mode.identifier.dropFirst("mode-".count))
        XCTAssertFalse(id.isEmpty)
        return id
    }

    private func openEditor(id: String, in app: XCUIApplication) {
        let edit = app.buttons["edit-mode-\(id)"]
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.textViews["rewritePromptEditor"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            // The active Form/List may be a collection view on newer iOS.
            // Prefer the foreground scroll surface when a nested sheet is open.
            let surfaces = app.scrollViews.allElementsBoundByIndex
                + app.collectionViews.allElementsBoundByIndex
                + app.tables.allElementsBoundByIndex
            let scroll = surfaces.last(where: { $0.exists && $0.isHittable }) ?? app
            scroll.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Unreachable control: \(element.identifier)\n\(app.debugDescription)")
    }

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        field.tap()
        field.press(forDuration: 1)
        // The native Select All action is reliable where a simulator's
        // hardware Command-A event can leave the caret at the beginning.
        let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Select All")).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), app.debugDescription)
        selectAll.tap()
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func expectLabel(_ expected: String, on element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let matching = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matching], timeout: 5), .completed)
    }

    private func waitForRewrite(in app: XCUIApplication) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["recordButton"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
