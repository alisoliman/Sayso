import UIKit
import XCTest
@testable import Sayso

@MainActor
final class DictationControllerTests: XCTestCase {
    private func storeURL() -> URL {
        URL.temporaryDirectory.appending(path: "SaysoControllerTests-\(UUID().uuidString).json")
    }

    private func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(description, file: file, line: line)
    }

    private func start(_ controller: DictationController, mode: WritingMode = .transcript, history: Bool = true) {
        controller.start(mode: mode, locale: "en-US", instructions: "", vocabulary: "", saveHistory: history)
    }

    func testPassivePreparationKeepsResultAndNeverStartsRecordingOrShowsFailure() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.prewarmFailure = StubFailure.interrupted
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        let previous = Dictation(text: "Keep this result.", original: "Keep this result.", mode: .transcript,
                                 duration: 1, localeIdentifier: "en-US")
        controller.current = previous
        controller.prepareForRecording(locale: "nl-NL", vocabulary: "Sayso\nAmsterdam")
        await waitUntil("Preparation runs") { speech.prewarmCalls == 1 }
        XCTAssertEqual(speech.preparedLocale, "nl-NL")
        XCTAssertEqual(speech.preparedVocabulary, ["Sayso", "Amsterdam"])
        XCTAssertFalse(speech.isRecording)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.current, previous)
        XCTAssertNil(controller.notice)
        start(controller)
        await waitUntil("Record remains available after readiness failure") { controller.phase == .recording }
        controller.cancel()
        await waitUntil("Cleanup finishes") { controller.phase == .idle }
    }

    func testMemoryPressureReleasesIdleModelsAndDefersReleaseDuringCapture() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        controller.appDidReceiveMemoryWarning()
        await waitUntil("Idle models release") { speech.releaseCalls == 1 }
        start(controller)
        await waitUntil("Recording starts") { controller.phase == .recording }
        controller.appDidReceiveMemoryWarning()
        controller.prepareForRecording(locale: "en-US", vocabulary: "")
        XCTAssertEqual(speech.releaseCalls, 1)
        XCTAssertEqual(speech.prewarmCalls, 0)
        XCTAssertTrue(speech.isRecording)
        controller.cancel()
        await waitUntil("Models release after capture cleanup") { speech.releaseCalls == 2 }
    }

    func testCancelledOldFinishCannotOverwriteNewRecording() async throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.stopText = "Keep my original thought."
        let suspended = SuspendedRewrite()
        defer { suspended.resume("Cleanup") }
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech,
                                              transformation: { _, _, _, _ in await suspended.wait() })
        start(controller, mode: .clean)
        await waitUntil("Recording should start") { controller.phase == .recording }
        controller.finish()
        await waitUntil("Rewrite should be suspended") { suspended.isWaiting }
        XCTAssertEqual(controller.store.entries.first?.original, speech.stopText)

        controller.cancel()
        await waitUntil("Cancel should finish") { controller.phase == .idle }
        start(controller)
        await waitUntil("A new recording should start") { controller.phase == .recording }
        let newStartedAt = try XCTUnwrap(controller.startedAt)

        suspended.resume("A stale rewrite must not be applied.")
        await waitUntil("Old rewrite should resume") { suspended.didReturn }
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(controller.startedAt, newStartedAt)
        XCTAssertNil(controller.current)
        XCTAssertEqual(controller.store.entries.map(\.text), [speech.stopText])
        controller.cancel()
        await waitUntil("Final cleanup should finish") { controller.phase == .idle }
    }

    func testOlderCancellationCompletionCannotResetNewOperation() async throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.suspendCancellation = true
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        start(controller)
        await waitUntil("Recording should start") { controller.phase == .recording }
        controller.cancel()
        await waitUntil("First cancellation should suspend") { speech.pendingCancellationCount == 1 }
        controller.cancel()
        await waitUntil("Second cancellation should suspend") { speech.pendingCancellationCount == 2 }
        speech.resumeCancellation(at: 1)
        await waitUntil("Newest cancellation should finish") { controller.phase == .idle }
        start(controller)
        await waitUntil("New recording should start") { controller.phase == .recording }
        let startedAt = try XCTUnwrap(controller.startedAt)

        speech.resumeCancellation(at: 0)
        await waitUntil("Both cancellation calls should return") { speech.finishedCancellations == 2 }
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(controller.startedAt, startedAt)
        speech.suspendCancellation = false
        controller.cancel()
        await waitUntil("Final cleanup should finish") { controller.phase == .idle }
    }

    func testFailedImportRetainsPartialTranscriptAndItsOriginal() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.filePartialText = "  Recover these words.\n"
        speech.fileResult = .failure(StubFailure.interrupted)
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        controller.importAudio(URL(filePath: "/unused-test-audio.m4a"), mode: .clean, locale: "en-US",
                               instructions: "", vocabulary: "", saveHistory: true,
                               writingStyle: WritingStyle(title: "Brief", prompt: "Write a brief update."))
        await waitUntil("Failed import should settle") { controller.phase == .idle }
        XCTAssertEqual(controller.current?.text, "Recover these words.")
        XCTAssertEqual(controller.current?.original, "Recover these words.")
        XCTAssertEqual(controller.current?.mode, .transcript)
        XCTAssertNil(controller.current?.writingStyle)
        XCTAssertEqual(DictationStore(fileURL: url).entries.first?.text, "Recover these words.")
        XCTAssertNotNil(controller.resultNote)
    }

    func testRepeatedInterruptionFinalizesOnlyOnce() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.stopText = "The words before the interruption."
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        start(controller)
        await waitUntil("Recording should start") { controller.phase == .recording }
        speech.onInterruption?()
        speech.onInterruption?()
        await waitUntil("Interrupted recording should settle") { controller.phase == .idle }
        XCTAssertEqual(speech.stopCalls, 1)
        XCTAssertEqual(controller.current?.text, speech.stopText)
        XCTAssertEqual(controller.store.entries.count, 1)
    }

    func testHistoryDisabledKeepsResultWithoutWritingIt() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.stopText = "This thought stays out of history."
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        start(controller, history: false)
        await waitUntil("Recording should start") { controller.phase == .recording }
        controller.finish()
        await waitUntil("Recording should finish") { controller.phase == .idle }
        XCTAssertEqual(controller.current?.text, speech.stopText)
        XCTAssertTrue(controller.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        controller.updateText("An edited private thought.")
        XCTAssertTrue(controller.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCopyWritesExactResultText() {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = DictationController(store: DictationStore(fileURL: url), speech: StubSpeech())
        let text = "Don't change €17.50.\nمرحبا 👋"
        controller.copy(text)
        XCTAssertEqual(UIPasteboard.general.string, text)
        XCTAssertTrue(controller.copied)
    }

    func testSavedHistoryEditsAndDeletionSynchronizeHomeWithoutResurrection() {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DictationStore(fileURL: url)
        let original = Dictation(text: "Saved text", original: "um saved text", mode: .clean, duration: 2, localeIdentifier: "en-US")
        XCTAssertTrue(store.save(original))
        let controller = DictationController(store: store, speech: StubSpeech())
        controller.current = original

        var edited = original
        edited.text = "Edited from history"
        XCTAssertTrue(store.save(edited))
        XCTAssertEqual(controller.current, edited)
        XCTAssertTrue(store.delete(edited.id))
        XCTAssertNil(controller.current)
        controller.updateText("A deleted entry must not return")
        XCTAssertTrue(store.entries.isEmpty)

        XCTAssertTrue(store.save(original))
        controller.current = original
        XCTAssertTrue(store.deleteAll())
        XCTAssertNil(controller.current)
    }

    func testUnrelatedHistoryChangesDoNotDiscardUnsavedCurrentResult() {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DictationStore(fileURL: url)
        let saved = Dictation(text: "Old saved thought", original: "Old saved thought", mode: .transcript, duration: 2, localeIdentifier: "en-US")
        XCTAssertTrue(store.save(saved))
        let controller = DictationController(store: store, speech: StubSpeech())
        let unsaved = Dictation(text: "An unsaved thought", original: "An unsaved thought", mode: .transcript, duration: 2, localeIdentifier: "en-US")
        controller.current = unsaved
        XCTAssertTrue(store.deleteAll())
        XCTAssertEqual(controller.current, unsaved)
        XCTAssertTrue(store.save(saved))
        XCTAssertEqual(controller.current, unsaved)
    }

    func testReworkUsesLatestManualEditsAndKeepsArchivalOriginal() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DictationStore(fileURL: url)
        var sources: [String] = []
        let controller = DictationController(store: store, speech: StubSpeech(), transformation: { text, _, _, _ in
            sources.append(text)
            return "A rewrite of the latest edits."
        })
        let original = Dictation(text: "First text", original: "um first text", mode: .clean, duration: 2, localeIdentifier: "en-US")
        XCTAssertTrue(store.save(original))
        controller.current = original
        controller.updateText("My deliberate manual changes.")
        controller.rework(mode: .notes, instructions: "", vocabulary: "")
        await waitUntil("Rewrite should finish") { controller.phase == .idle }
        XCTAssertEqual(sources, ["My deliberate manual changes."])
        XCTAssertEqual(controller.current?.text, "A rewrite of the latest edits.")
        XCTAssertEqual(controller.current?.original, "um first text")
        XCTAssertEqual(store.entries.first?.original, "um first text")
    }

    func testOriginalModeRestoresArchiveWithoutCallingModel() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = DictationController(store: DictationStore(fileURL: url), speech: StubSpeech(), transformation: { _, _, _, _ in
            XCTFail("Original restoration must not need a model")
            return "Wrong text"
        })
        controller.current = Dictation(text: "A manual edit", original: "um original words", mode: .custom, duration: 2, localeIdentifier: "en-US",
                                       writingStyle: WritingStyle(title: "Brief", prompt: "Write a brief update."))
        controller.rework(mode: .transcript, instructions: "", vocabulary: "",
                          writingStyle: WritingStyle(id: WritingMode.transcript.rawValue, title: "Original", prompt: WritingMode.transcript.instructions))
        await waitUntil("Original restoration should finish") { controller.phase == .idle }
        XCTAssertEqual(controller.current?.text, "um original words")
        XCTAssertEqual(controller.current?.original, "um original words")
        XCTAssertEqual(controller.current?.mode, .transcript)
        XCTAssertNil(controller.current?.writingStyle)
    }

    func testFailedReworkPreservesCurrentManualEdits() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = DictationController(store: DictationStore(fileURL: url), speech: StubSpeech(), transformation: { _, _, _, _ in
            throw IntelligenceError.refused
        })
        let edited = Dictation(text: "My deliberate edits", original: "um original words", mode: .custom, duration: 2, localeIdentifier: "en-US",
                               writingStyle: WritingStyle(title: "Friendly", prompt: "Use a friendly tone."))
        XCTAssertTrue(controller.store.save(edited))
        controller.current = edited
        controller.rework(mode: .notes, instructions: "", vocabulary: "",
                          writingStyle: WritingStyle(title: "Brief", prompt: "Write a brief update."))
        await waitUntil("Failed rewrite should settle") { controller.phase == .idle }
        XCTAssertEqual(controller.current, edited)
        XCTAssertEqual(controller.store.entries, [edited])
        XCTAssertNotNil(controller.resultNote)
    }

    func testCustomRewriteForwardsFrozenPromptAndSavesModeIdentity() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var style = WritingStyle(title: "Team update", prompt: "Use short paragraphs and keep uncertainties.")
        let selectedStyle = style
        var receivedMode: WritingMode?
        var receivedPrompt: String?
        var receivedVocabulary: [String] = []
        let controller = DictationController(store: DictationStore(fileURL: url), speech: StubSpeech(), transformation: { text, mode, prompt, vocabulary in
            XCTAssertEqual(text, "My corrected update.")
            receivedMode = mode
            receivedPrompt = prompt
            receivedVocabulary = vocabulary
            return "A team update."
        })
        let saved = Dictation(text: "My corrected update.", original: "um my update", mode: .clean, duration: 2, localeIdentifier: "en-US")
        XCTAssertTrue(controller.store.save(saved))
        controller.reworkSaved(saved.id, mode: .clean, instructions: "Old custom instructions", vocabulary: "Sayso\nAlex", writingStyle: style)
        style.title = "Renamed mode"
        style.prompt = "A different prompt."
        await waitUntil("Custom rewrite should finish") { controller.phase == .idle }

        XCTAssertEqual(receivedMode, .custom)
        XCTAssertEqual(receivedPrompt, selectedStyle.prompt)
        XCTAssertEqual(receivedVocabulary, ["Sayso", "Alex"])
        XCTAssertEqual(controller.current?.writingStyle, selectedStyle)
        XCTAssertEqual(controller.current?.mode, .custom)
        XCTAssertEqual(controller.current?.modeTitle, "Team update")
        XCTAssertEqual(controller.current?.original, saved.original)
        XCTAssertEqual(controller.current?.id, saved.id)
        XCTAssertEqual(DictationStore(fileURL: url).entries.first, controller.current)
    }

    func testEditedBuiltInPromptUsesCustomTransformationAndKeepsBuiltInIdentity() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let style = WritingStyle(id: WritingMode.notes.rawValue, title: "Notes", prompt: "Use a numbered list of complete thoughts.")
        var receivedMode: WritingMode?
        var receivedPrompt: String?
        let controller = DictationController(store: DictationStore(fileURL: url), speech: StubSpeech(), transformation: { _, mode, prompt, _ in
            receivedMode = mode
            receivedPrompt = prompt
            return "1. A complete thought."
        })
        controller.current = Dictation(text: "A complete thought.", original: "um a complete thought", mode: .clean, duration: 2, localeIdentifier: "en-US")
        controller.rework(mode: .notes, instructions: "", vocabulary: "", writingStyle: style)
        await waitUntil("Edited built-in rewrite should finish") { controller.phase == .idle }

        XCTAssertEqual(receivedMode, .custom)
        XCTAssertEqual(receivedPrompt, style.prompt)
        XCTAssertEqual(controller.current?.mode, .notes)
        XCTAssertEqual(controller.current?.writingStyle, style)
        XCTAssertEqual(controller.current?.modeSymbol, WritingMode.notes.symbol)
    }

    func testCancelledCustomRewriteKeepsPreviousTextAndStyle() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let suspended = SuspendedRewrite()
        defer { suspended.resume("Cleanup") }
        let controller = DictationController(store: DictationStore(fileURL: url), speech: StubSpeech(), transformation: { _, _, _, _ in
            await suspended.wait()
        })
        let previous = Dictation(text: "My manual edits.", original: "um the original", mode: .custom, duration: 2, localeIdentifier: "en-US",
                                  writingStyle: WritingStyle(title: "Friendly", prompt: "Use a friendly tone."))
        XCTAssertTrue(controller.store.save(previous))
        controller.current = previous
        controller.rework(mode: .custom, instructions: "", vocabulary: "",
                          writingStyle: WritingStyle(title: "Brief", prompt: "Write a brief update."))
        await waitUntil("Rewrite should suspend") { suspended.isWaiting }
        controller.cancel()
        await waitUntil("Cancellation should finish") { controller.phase == .idle }
        suspended.resume("Cancelled rewrite")
        await waitUntil("Cancelled rewrite should return") { suspended.didReturn }

        XCTAssertEqual(controller.current, previous)
        XCTAssertEqual(DictationStore(fileURL: url).entries, [previous])
    }

    func testRecordingFreezesSelectedStyleBeforeAudioFinishes() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.stopText = "The recorded thought."
        var style = WritingStyle(title: "Brief", prompt: "Write a brief update.")
        let selectedStyle = style
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech, transformation: { text, mode, prompt, _ in
            XCTAssertEqual(text, speech.stopText)
            XCTAssertEqual(mode, .custom)
            XCTAssertEqual(prompt, selectedStyle.prompt)
            return "A brief recording."
        })
        controller.start(mode: .custom, locale: "en-US", instructions: "Old preferences", vocabulary: "", saveHistory: true, writingStyle: style)
        await waitUntil("Recording should start") { controller.phase == .recording }
        style.title = "Changed during recording"
        style.prompt = "Use a different format."
        controller.finish()
        await waitUntil("Recording should finish") { controller.phase == .idle }

        XCTAssertEqual(controller.current?.text, "A brief recording.")
        XCTAssertEqual(controller.current?.writingStyle, selectedStyle)
        XCTAssertEqual(controller.store.entries.first?.writingStyle, selectedStyle)
    }

    func testImportFreezesSelectedStyleBeforeTranscriptionBegins() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.fileResult = .success("The imported thought.")
        var style = WritingStyle(id: WritingMode.message.rawValue, title: "Message", prompt: WritingMode.message.instructions)
        let selectedStyle = style
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech, transformation: { text, mode, prompt, _ in
            XCTAssertEqual(text, "The imported thought.")
            XCTAssertEqual(mode, .message)
            XCTAssertEqual(prompt, selectedStyle.prompt)
            return "A message from the import."
        })
        controller.importAudio(URL(filePath: "/unused-test-audio.m4a"), mode: .message, locale: "en-US",
                               instructions: "Old preferences", vocabulary: "", saveHistory: true, writingStyle: style)
        style.prompt = "An edited message prompt."
        await waitUntil("Import should finish") { controller.phase == .idle }

        XCTAssertEqual(controller.current?.text, "A message from the import.")
        XCTAssertEqual(controller.current?.writingStyle, selectedStyle)
        XCTAssertEqual(controller.current?.mode, .message)
    }

    func testHistoryRewriteUsesLatestSavedEditsAndUpdatesSameEntry() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DictationStore(fileURL: url)
        let speech = StubSpeech()
        var sources: [String] = []
        let controller = DictationController(store: store, speech: speech, transformation: { text, _, _, _ in
            sources.append(text)
            return "The rewritten saved thought."
        })
        // A prior private recording must not turn subsequent edits to a saved item private.
        start(controller, history: false)
        await waitUntil("Private recording starts") { controller.phase == .recording }
        controller.cancel()
        await waitUntil("Cancellation finishes") { controller.phase == .idle }
        let saved = Dictation(text: "Corrected from history.", original: "um from history", mode: .clean, duration: 2, localeIdentifier: "en-US")
        XCTAssertTrue(store.save(saved))
        controller.reworkSaved(saved.id, mode: .message, instructions: "", vocabulary: "")
        await waitUntil("History rewrite finishes") { controller.phase == .idle }
        XCTAssertEqual(sources, [saved.text])
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, saved.id)
        XCTAssertEqual(store.entries.first?.original, saved.original)
        XCTAssertEqual(store.entries.first?.text, "The rewritten saved thought.")
        XCTAssertEqual(controller.current, store.entries.first)
    }

    func testHistoryRewriteCannotResurrectDeletedEntry() {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = DictationController(store: DictationStore(fileURL: url), speech: StubSpeech())
        let saved = Dictation(text: "Deleted thought", original: "Deleted thought", mode: .transcript, duration: 1, localeIdentifier: "en-US")
        XCTAssertTrue(controller.store.save(saved))
        XCTAssertTrue(controller.store.delete(saved.id))
        controller.reworkSaved(saved.id, mode: .clean, instructions: "", vocabulary: "")
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.current)
        XCTAssertTrue(controller.store.entries.isEmpty)
    }

    func testFailedPreparationCannotMakePreviousPrivateResultPersistent() async {
        await verifyPreviousResultPolicyAfterFailedAttempt(previousHistory: false, cancelled: false, importing: false)
    }

    func testCancelledPreparationCannotMakePreviousPrivateResultPersistent() async {
        await verifyPreviousResultPolicyAfterFailedAttempt(previousHistory: false, cancelled: true, importing: false)
    }

    func testEmptyImportCannotMakePreviousPrivateResultPersistent() async {
        await verifyPreviousResultPolicyAfterFailedAttempt(previousHistory: false, cancelled: false, importing: true)
    }

    func testEmptyPrivateImportDoesNotDisableEditsToSavedResult() async {
        await verifyPreviousResultPolicyAfterFailedAttempt(previousHistory: true, cancelled: false, importing: true)
    }

    private func verifyPreviousResultPolicyAfterFailedAttempt(previousHistory: Bool, cancelled: Bool, importing: Bool) async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.stopText = "The previous thought."
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech,
            transformation: { text, _, _, _ in text + " Rewritten." })
        start(controller, history: previousHistory)
        await waitUntil("Initial recording starts") { controller.phase == .recording }
        controller.finish()
        await waitUntil("Initial result settles") { controller.phase == .idle }
        let originalID = controller.current?.id
        speech.partialText = ""
        if importing {
            speech.fileResult = .success("")
            controller.importAudio(URL(filePath: "/empty.wav"), mode: .transcript, locale: "en-US", instructions: "", vocabulary: "", saveHistory: !previousHistory)
        } else {
            speech.startResult = .failure(StubFailure.interrupted)
            start(controller, history: !previousHistory)
            if cancelled { controller.cancel() }
        }
        await waitUntil("Failed new attempt settles") { controller.phase == .idle }
        XCTAssertEqual(controller.current?.id, originalID)
        controller.updateText("An edit to the previous thought.")
        controller.rework(mode: .clean, instructions: "", vocabulary: "")
        await waitUntil("Rewrite settles") { controller.phase == .idle }
        XCTAssertEqual(controller.current?.text, "An edit to the previous thought. Rewritten.")
        XCTAssertEqual(controller.store.entries.count, previousHistory ? 1 : 0)
        XCTAssertEqual(FileManager.default.fileExists(atPath: url.path), previousHistory)
        if previousHistory { XCTAssertEqual(controller.store.entries.first?.text, controller.current?.text) }
    }

    func testBackgroundCheckpointKeepsDurationAtStopInsteadOfFinalizationDelay() async throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        let suspended = SuspendedRewrite()
        defer { suspended.resume("Final captured words.") }
        speech.stopOverride = { await suspended.wait() }
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        start(controller)
        await waitUntil("Recording starts") { controller.phase == .recording }
        speech.partialText = "Captured before stop."
        controller.startedAt = Date().addingTimeInterval(-10)
        controller.finish()
        await waitUntil("Stop waits for final text") { suspended.isWaiting }
        // Simulate elapsed finalization time without a slow, wall-clock-dependent test.
        controller.startedAt = Date().addingTimeInterval(-30)
        controller.appDidEnterBackground()
        let checkpoint = try XCTUnwrap(controller.store.entries.first)
        XCTAssertEqual(checkpoint.duration, 10, accuracy: 1)
        suspended.resume("Final captured words.")
        await waitUntil("Finalization settles") { controller.phase == .idle }
        XCTAssertEqual(controller.store.entries.count, 1)
        XCTAssertEqual(controller.current?.duration ?? 0, 10, accuracy: 1)
        XCTAssertEqual(controller.current?.text, "Final captured words.")
    }

    func testImmediateBackgroundBeforeImportCannotCheckpointPreviousPrivateWords() async {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let speech = StubSpeech()
        speech.stopText = "A private previous transcript."
        let controller = DictationController(store: DictationStore(fileURL: url), speech: speech)
        start(controller, history: false)
        await waitUntil("Private recording starts") { controller.phase == .recording }
        controller.finish()
        await waitUntil("Private recording finishes") { controller.phase == .idle }
        let previousID = controller.current?.id
        // Speech retains its most recent transcript after finalization, as the real service does.
        speech.partialText = speech.stopText
        controller.importAudio(URL(filePath: "/not-started.wav"), mode: .clean, locale: "en-US", instructions: "", vocabulary: "", saveHistory: true)
        // Deliberately background before the newly created import Task has run.
        controller.appDidEnterBackground()
        await waitUntil("Import cancellation settles") { controller.phase == .idle }
        XCTAssertEqual(controller.current?.id, previousID)
        XCTAssertTrue(controller.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
private final class SuspendedRewrite {
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var didReturn = false
    var isWaiting: Bool { continuation != nil }

    func wait() async -> String {
        let result = await withCheckedContinuation { continuation = $0 }
        didReturn = true
        return result
    }

    func resume(_ text: String) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: text)
    }
}

@MainActor
private final class StubSpeech: SpeechTranscribing {
    var partialText = ""
    var level = 0.0
    var status = "Ready"
    var isRecording = false
    var onInterruption: (() -> Void)?
    var stopText = ""
    var startResult: Result<Void, Error> = .success(())
    var stopOverride: (() async throws -> String)?
    var stopCalls = 0
    var prewarmCalls = 0
    var releaseCalls = 0
    var preparedLocale: String?
    var preparedVocabulary: [String] = []
    var prewarmFailure: Error?
    var fileResult: Result<String, Error> = .success("")
    var filePartialText: String?
    var suspendCancellation = false
    private var cancellations: [CheckedContinuation<Void, Never>?] = []
    private(set) var finishedCancellations = 0
    var pendingCancellationCount: Int { cancellations.count }

    func resetTranscript() { partialText = ""; level = 0 }
    func prewarm(localeIdentifier: String, contextualStrings: [String]) async throws {
        prewarmCalls += 1
        preparedLocale = localeIdentifier
        preparedVocabulary = contextualStrings
        if let prewarmFailure { throw prewarmFailure }
    }
    func releasePreparedResources() async { releaseCalls += 1 }
    func start(localeIdentifier: String, contextualStrings: [String]) async throws { try startResult.get(); isRecording = true }
    func stop() async throws -> String {
        stopCalls += 1
        isRecording = false
        if let stopOverride { return try await stopOverride() }
        return stopText
    }
    func transcribeFile(at url: URL, localeIdentifier: String, contextualStrings: [String]) async throws -> String {
        if let filePartialText { partialText = filePartialText }
        return try fileResult.get()
    }
    func cancel() async {
        isRecording = false
        if suspendCancellation {
            await withCheckedContinuation { cancellations.append($0) }
        }
        finishedCancellations += 1
    }
    func resumeCancellation(at index: Int) {
        guard cancellations.indices.contains(index) else {
            XCTFail("No suspended cancellation at index \(index)")
            return
        }
        let pending = cancellations[index]
        cancellations[index] = nil
        pending?.resume()
    }
}

private enum StubFailure: Error { case interrupted }
