import Foundation
import XCTest
@testable import Sayso

/// Exercises the app's cross-process lifecycle with real temporary mailboxes.
/// Speech and ActivityKit are fakes: these tests make no device/background-audio claim.
@MainActor
final class CrossAppRecordingTests: XCTestCase {
    private func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(description, file: file, line: line)
    }

    private func start(_ fixture: CrossAppFixture, mode: WritingMode = .transcript,
                       history: Bool = true, destination: DictationController.Destination = .keyboard) {
        fixture.controller.start(mode: mode, locale: "en-US", instructions: "", vocabulary: "",
                                 saveHistory: history, destination: destination)
    }

    func testExplicitKeyboardRecordingContinuesInBackgroundAndStopPublishesFinalWords() async throws {
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        start(fixture)
        await waitUntil("Keyboard recording starts") { fixture.controller.phase == .recording }
        let sessionID = try XCTUnwrap(fixture.coordinator.sessionID)
        fixture.speech.partialText = "A provisional thought."
        fixture.controller.appDidEnterBackground()

        XCTAssertEqual(fixture.controller.phase, .recording)
        XCTAssertEqual(fixture.speech.stopCalls, 0)
        XCTAssertTrue(fixture.speech.isRecording)
        XCTAssertEqual(fixture.store.entries.map(\.id), [sessionID])
        XCTAssertNil(try fixture.handoff.latest())

        fixture.speech.stopText = "The complete thought, including its final word."
        let now = Date()
        try fixture.sessions.send(.stop, sessionID: sessionID, now: now)
        fixture.coordinator.poll(now: now)
        fixture.coordinator.poll(now: now)
        await waitUntil("Keyboard stop finishes") { fixture.controller.phase == .idle }

        XCTAssertEqual(fixture.speech.stopCalls, 1)
        XCTAssertFalse(fixture.speech.isRecording)
        XCTAssertEqual(fixture.store.entries.count, 1)
        XCTAssertEqual(fixture.store.entries.first?.id, sessionID)
        XCTAssertEqual(fixture.store.entries.first?.text, fixture.speech.stopText)
        XCTAssertEqual(try fixture.handoff.latest()?.text, fixture.speech.stopText)
        XCTAssertEqual(try fixture.handoff.latest()?.id, sessionID)
        XCTAssertEqual(try fixture.handoff.latest()?.recordingSessionID, sessionID)
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertEqual(fixture.activity.endedPhases, [.ready])
    }

    func testKeyboardStopUsesChosenModeFromTheRecordingCatalog() async throws {
        var usedMode: WritingMode?
        var usedInstructions: String?
        let fixture = CrossAppFixture(transformation: { _, mode, instructions, _ in
            usedMode = mode
            usedInstructions = instructions
            return "- The chosen notes."
        })
        defer { fixture.removeFiles() }
        start(fixture, mode: .clean)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        let session = try XCTUnwrap(fixture.sessions.latest())
        XCTAssertEqual(session.selectedModeID, WritingMode.clean.rawValue)
        XCTAssertTrue(session.availableModes?.contains(where: { $0.id == WritingMode.notes.rawValue }) == true)
        let now = Date()
        try fixture.sessions.send(.stop, sessionID: session.id, modeID: WritingMode.notes.rawValue, now: now)
        fixture.coordinator.poll(now: now)
        await waitUntil("Chosen mode finishes") { fixture.controller.phase == .idle }
        XCTAssertEqual(usedMode, .notes)
        XCTAssertEqual(usedInstructions, WritingMode.notes.instructions)
        XCTAssertEqual(try fixture.handoff.latest()?.text, "- The chosen notes.")
    }

    func testKeyboardOriginalChoiceSkipsWritingAndManualReshareClearsProvenance() async throws {
        var writingCalls = 0
        let fixture = CrossAppFixture(transformation: { text, _, _, _ in writingCalls += 1; return text })
        defer { fixture.removeFiles() }
        start(fixture, mode: .clean)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        let id = try XCTUnwrap(fixture.coordinator.sessionID)
        let now = Date()
        try fixture.sessions.send(.stop, sessionID: id, modeID: WritingMode.transcript.rawValue, now: now)
        fixture.coordinator.poll(now: now)
        await waitUntil("Original finishes") { fixture.controller.phase == .idle }
        XCTAssertEqual(writingCalls, 0)
        XCTAssertEqual(try fixture.handoff.latest()?.recordingSessionID, id)
        try fixture.handoff.publish(text: "An explicit later edit.", id: id)
        XCTAssertNil(try fixture.handoff.latest()?.recordingSessionID)
    }

    func testKeyboardModeWithLongDisplayNameRetainsItsPrompt() async throws {
        var usedInstructions: String?
        let fixture = CrossAppFixture(transformation: { text, _, instructions, _ in
            usedInstructions = instructions
            return text
        })
        defer { fixture.removeFiles() }
        let style = WritingStyle(title: String(repeating: "A long saved mode ", count: 12), prompt: "Keep a concise complete paragraph.")
        fixture.controller.start(mode: .custom, locale: "en-US", instructions: "", vocabulary: "",
                                 saveHistory: false, destination: .keyboard, writingStyle: style)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        let session = try XCTUnwrap(fixture.sessions.latest())
        let sharedStyle = try XCTUnwrap(session.availableModes?.first(where: { $0.id == style.id }))
        XCTAssertEqual(session.selectedModeID, style.id)
        XCTAssertLessThanOrEqual(sharedStyle.title.utf8.count, 120)
        let now = Date()
        try fixture.sessions.send(.stop, sessionID: session.id, modeID: style.id, now: now)
        fixture.coordinator.poll(now: now)
        await waitUntil("Selected saved mode finishes") { fixture.controller.phase == .idle }
        XCTAssertEqual(usedInstructions, style.prompt)
        XCTAssertEqual(fixture.controller.current?.writingStyle, style)
    }

    func testOrdinaryRecordingStillStopsOnBackgroundWithoutSharingOrInvokingWriting() async throws {
        var writingCalls = 0
        let fixture = CrossAppFixture(transformation: { text, _, _, _ in
            writingCalls += 1
            return "Unexpected rewrite of " + text
        })
        defer { fixture.removeFiles() }
        fixture.speech.stopText = "Keep these ordinary recording words."
        start(fixture, mode: .clean, destination: .app)
        await waitUntil("Ordinary recording starts") { fixture.controller.phase == .recording }
        fixture.speech.partialText = "Keep these ordinary"
        fixture.controller.appDidEnterBackground()
        await waitUntil("Ordinary background recording finishes") { fixture.controller.phase == .idle }

        XCTAssertEqual(fixture.speech.stopCalls, 1)
        XCTAssertEqual(writingCalls, 0)
        XCTAssertEqual(fixture.controller.current?.text, fixture.speech.stopText)
        XCTAssertEqual(fixture.controller.current?.mode, .transcript)
        XCTAssertTrue(fixture.activity.startedIDs.isEmpty)
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertNil(try fixture.handoff.latest())
    }

    func testPrivateKeyboardRecordingSharesChosenResultWithoutCreatingHistory() async throws {
        let fixture = CrossAppFixture(transformation: { _, _, _, _ in "A polished private result." })
        defer { fixture.removeFiles() }
        fixture.speech.stopText = "um a private result"
        start(fixture, mode: .clean, history: false)
        await waitUntil("Private keyboard recording starts") { fixture.controller.phase == .recording }
        fixture.speech.partialText = "um a private"
        fixture.controller.appDidEnterBackground()
        XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.historyURL.path))
        fixture.controller.finish()
        await waitUntil("Private keyboard result finishes") { fixture.controller.phase == .idle }

        XCTAssertEqual(try fixture.handoff.latest()?.text, "A polished private result.")
        XCTAssertEqual(fixture.controller.current?.original, fixture.speech.stopText)
        XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.historyURL.path))
        fixture.controller.updateText("My edited private result.")
        XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.historyURL.path))
        // Insertion uses the completed result until the person explicitly sends an edit.
        XCTAssertEqual(try fixture.handoff.latest()?.text, "A polished private result.")
    }

    func testDiscardRemovesOnlyCurrentProvisionalHistoryAndPublishesNothing() async throws {
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        let prior = CrossAppFixture.entry("An earlier saved dictation.")
        XCTAssertTrue(fixture.store.save(prior))
        try fixture.handoff.publish(text: "Previously shared result")
        start(fixture)
        await waitUntil("Keyboard recording starts") { fixture.controller.phase == .recording }
        let sessionID = try XCTUnwrap(fixture.coordinator.sessionID)
        XCTAssertNil(try fixture.handoff.latest())
        fixture.speech.partialText = "Discard this provisional text."
        fixture.controller.appDidEnterBackground()
        XCTAssertEqual(Set(fixture.store.entries.map(\.id)), Set([prior.id, sessionID]))

        let now = Date()
        try fixture.sessions.send(.cancel, sessionID: sessionID, now: now)
        fixture.coordinator.poll(now: now)
        await waitUntil("Discard finishes") { fixture.controller.phase == .idle }

        XCTAssertEqual(fixture.speech.stopCalls, 0)
        XCTAssertEqual(fixture.speech.cancelCalls, 1)
        XCTAssertFalse(fixture.speech.isRecording)
        XCTAssertEqual(fixture.store.entries, [prior])
        XCTAssertEqual(DictationStore(fileURL: fixture.historyURL).entries, [prior])
        XCTAssertNil(fixture.controller.current)
        XCTAssertNil(try fixture.handoff.latest())
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertEqual(fixture.activity.endedPhases, [.cancelled])
    }

    func testDiscardDuringWritingCannotPublishOrResurrectLateRewrite() async throws {
        let suspended = CrossAppSuspension<String>()
        defer { suspended.resume("Cleanup") }
        let fixture = CrossAppFixture(transformation: { _, _, _, _ in await suspended.wait() })
        defer { fixture.removeFiles() }
        let prior = CrossAppFixture.entry("Keep this earlier entry.")
        XCTAssertTrue(fixture.store.save(prior))
        fixture.speech.stopText = "Discard this finished source as well."
        start(fixture, mode: .clean)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        fixture.controller.finish()
        await waitUntil("Writing waits") { suspended.isWaiting }
        XCTAssertEqual(fixture.store.entries.count, 2)
        fixture.controller.cancel()
        await waitUntil("Discard settles") { fixture.controller.phase == .idle }
        suspended.resume("This stale rewrite must never return.")
        await waitUntil("Old writing returns") { suspended.didReturn }
        for _ in 0..<10 { await Task.yield() }

        XCTAssertNil(fixture.controller.current)
        XCTAssertEqual(fixture.store.entries, [prior])
        XCTAssertNil(try fixture.handoff.latest())
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertEqual(fixture.activity.endedPhases, [.cancelled])
    }

    func testWritingExpirationPublishesRetainedSourceAndLateRewriteCannotTouchNextRecording() async throws {
        let suspended = CrossAppSuspension<String>()
        defer { suspended.resume("Cleanup") }
        let fixture = CrossAppFixture(transformation: { _, _, _, _ in await suspended.wait() })
        defer { fixture.removeFiles() }
        fixture.speech.stopText = "Keep the source with €140, not €400."
        start(fixture, mode: .clean)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        let firstID = try XCTUnwrap(fixture.coordinator.sessionID)
        fixture.controller.finish()
        await waitUntil("Writing waits") { suspended.isWaiting }
        fixture.controller.appDidEnterBackground()
        XCTAssertEqual(fixture.controller.phase, .refining)
        fixture.coordinator.poll(completionElapsed: KeyboardRecordingSessionStore.completionAllowance)
        await waitUntil("Completion expiration settles") { fixture.controller.phase == .idle }

        let retained = try XCTUnwrap(try fixture.handoff.latest())
        XCTAssertEqual(retained.id, firstID)
        XCTAssertEqual(retained.text, fixture.speech.stopText)
        XCTAssertEqual(fixture.controller.current?.mode, .transcript)
        XCTAssertEqual(fixture.activity.endedPhases, [.ready])
        XCTAssertEqual(fixture.store.entries.first?.text, fixture.speech.stopText)

        start(fixture, destination: .app)
        await waitUntil("Next recording starts") { fixture.controller.phase == .recording }
        let nextStartedAt = fixture.controller.startedAt
        suspended.resume("A late rewrite that must be ignored.")
        await waitUntil("Stale writing returns") { suspended.didReturn }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(fixture.controller.phase, .recording)
        XCTAssertEqual(fixture.controller.startedAt, nextStartedAt)
        XCTAssertNil(fixture.controller.current)
        XCTAssertEqual(try fixture.handoff.latest(), retained)
        XCTAssertEqual(fixture.store.entries.map(\.id), [firstID])
        XCTAssertEqual(fixture.store.entries.first?.text, retained.text)
        fixture.controller.cancel()
        await waitUntil("Next recording cleanup finishes") { fixture.controller.phase == .idle }
    }

    func testQueuedDiscardWinsWhenWritingFinishesBeforeTheNextMailboxPoll() async throws {
        let suspended = CrossAppSuspension<String>()
        defer { suspended.resume("Cleanup") }
        let fixture = CrossAppFixture(transformation: { _, _, _, _ in await suspended.wait() })
        defer { fixture.removeFiles() }
        fixture.speech.stopText = "A result the person is discarding."
        start(fixture, mode: .clean)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        let sessionID = try XCTUnwrap(fixture.coordinator.sessionID)
        fixture.controller.finish()
        await waitUntil("Writing waits") { suspended.isWaiting }
        // The keyboard has committed Discard, but the regular 500 ms poll has
        // not fired. Finishing writing must not silently remove that command.
        try fixture.sessions.send(.cancel, sessionID: sessionID)
        suspended.resume("Do not share this completed rewrite.")
        await waitUntil("Queued discard settles") { fixture.controller.phase == .idle }

        XCTAssertNil(fixture.controller.current)
        XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertNil(try fixture.handoff.latest())
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertEqual(fixture.activity.endedPhases, [.cancelled])
    }

    func testCompletionDeadlineDuringDiscardCleanupCannotRepublishDiscardedWords() async throws {
        let writing = CrossAppSuspension<String>()
        let cleanup = CrossAppSuspension<Void>()
        defer { writing.resume("Cleanup"); cleanup.resume(()) }
        let cleanupTask = Task { await cleanup.wait() }
        let fixture = CrossAppFixture(transformation: { _, _, _, _ in await writing.wait() })
        defer { fixture.removeFiles() }
        fixture.speech.cancelOverride = { await cleanupTask.value }
        fixture.speech.stopText = "Words that must stay discarded."
        start(fixture, mode: .clean)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        fixture.speech.partialText = fixture.speech.stopText
        fixture.controller.finish()
        await waitUntil("Writing waits") { writing.isWaiting }
        fixture.controller.cancel()
        await waitUntil("Discard waits for speech cleanup") { fixture.speech.cancelCalls == 1 }
        XCTAssertEqual(fixture.controller.phase, .finishing)
        XCTAssertNil(fixture.controller.current)
        XCTAssertTrue(fixture.store.entries.isEmpty)

        // Expiration can arrive just after a local Discard while a service is
        // still releasing resources. It must never checkpoint or share again.
        fixture.coordinator.poll(completionElapsed: KeyboardRecordingSessionStore.completionAllowance)
        XCTAssertNil(fixture.controller.current)
        XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertNil(try fixture.handoff.latest())
        cleanup.resume(())
        await cleanupTask.value
        await waitUntil("Discard cleanup settles") { fixture.controller.phase == .idle }
        writing.resume("The late rewrite is also discarded.")
        await waitUntil("Stale writing returns") { writing.didReturn }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(fixture.controller.current)
        XCTAssertNil(try fixture.handoff.latest())
        XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertEqual(fixture.activity.endedPhases, [.cancelled])
    }

    func testCommittedCompletionDisablesDiscardAndIgnoresAStaleCancelAction() async throws {
        let suspended = CrossAppSuspension<Void>()
        defer { suspended.resume(()) }
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        fixture.activity.endOverride = { await suspended.wait() }
        fixture.speech.stopText = "The result whose completion is being displayed."
        start(fixture, mode: .clean)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        fixture.controller.finish()
        await waitUntil("System activity dismissal waits") { suspended.isWaiting }

        // The result is committed before the system's dismissal animation
        // finishes. A queued tap from the previous busy UI must do nothing.
        XCTAssertFalse(fixture.controller.canCancel)
        let committed = try XCTUnwrap(try fixture.handoff.latest())
        let committedEntry = try XCTUnwrap(fixture.controller.current)
        let readyNote = fixture.controller.resultNote
        fixture.controller.appDidEnterBackground()
        XCTAssertEqual(fixture.controller.resultNote, readyNote)
        fixture.controller.cancel()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(fixture.controller.current, committedEntry)
        XCTAssertEqual(fixture.store.entries, [committedEntry])
        XCTAssertEqual(try fixture.handoff.latest(), committed)
        XCTAssertEqual(committed.text, fixture.speech.stopText)
        suspended.resume(())
        await waitUntil("Activity dismissal returns") { suspended.didReturn }
        await waitUntil("Committed completion settles") { fixture.controller.phase == .idle }
        XCTAssertEqual(fixture.controller.phase, .idle)
    }

    func testFailedLiveActivityCancelsMicrophoneAndRetainsPreviousSharedResult() async throws {
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        let prior = try fixture.handoff.publish(text: "Previously shared, deliberately kept.")
        fixture.activity.startFailure = CrossAppFailure.activityUnavailable
        start(fixture)
        await waitUntil("Failed activity setup settles") { fixture.controller.phase == .idle }

        XCTAssertEqual(fixture.speech.startCalls, 1)
        XCTAssertEqual(fixture.speech.cancelCalls, 1)
        XCTAssertFalse(fixture.speech.isRecording)
        XCTAssertNotNil(fixture.controller.notice)
        XCTAssertNil(fixture.coordinator.sessionID)
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertEqual(try fixture.handoff.latest(), prior)
        XCTAssertEqual(fixture.activity.endedPhases, [.failed])
    }

    func testFinishingExpirationRefreshesEarlierCheckpointWithLatestCapturedWords() async throws {
        let suspended = CrossAppSuspension<String>()
        defer { suspended.resume("Cleanup") }
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        fixture.speech.stopOverride = { await suspended.wait() }
        start(fixture)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        fixture.speech.partialText = "The beginning of the thought."
        fixture.controller.appDidEnterBackground()
        XCTAssertEqual(fixture.controller.current?.text, fixture.speech.partialText)
        let sessionID = fixture.controller.current?.id

        fixture.controller.finish()
        await waitUntil("Speech finalization waits") { suspended.isWaiting }
        fixture.speech.partialText = "The beginning of the thought, plus the final captured words."
        fixture.coordinator.poll(completionElapsed: KeyboardRecordingSessionStore.completionAllowance)
        await waitUntil("Finishing expiration settles") { fixture.controller.phase == .idle }
        XCTAssertEqual(try fixture.handoff.latest()?.id, sessionID)
        XCTAssertEqual(try fixture.handoff.latest()?.text, fixture.speech.partialText)
        XCTAssertEqual(fixture.controller.current?.original, fixture.speech.partialText)
        XCTAssertEqual(fixture.store.entries.count, 1)
        XCTAssertEqual(fixture.store.entries.first?.text, fixture.speech.partialText)

        let retained = try fixture.handoff.latest()
        suspended.resume("A completion arriving after cancellation must be ignored.")
        await waitUntil("Stale finalization returns") { suspended.didReturn }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(try fixture.handoff.latest(), retained)
        XCTAssertEqual(fixture.controller.phase, .idle)
    }

    func testSharingSetupFailureEndsVisibleActivityAndCancelsMicrophone() async throws {
        let fixture = CrossAppFixture(unavailableHandoff: true)
        defer { fixture.removeFiles() }
        start(fixture)
        await waitUntil("Failed mailbox setup settles") { fixture.controller.phase == .idle }

        XCTAssertEqual(fixture.activity.startedIDs.count, 1)
        XCTAssertEqual(fixture.activity.endedPhases, [.failed])
        XCTAssertEqual(fixture.speech.cancelCalls, 1)
        XCTAssertFalse(fixture.speech.isRecording)
        XCTAssertNil(fixture.coordinator.sessionID)
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertTrue(fixture.store.entries.isEmpty)
    }

    func testLiveActivityDismissalStopsOnceAndIgnoresAnotherSessionsDismissal() async throws {
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        fixture.speech.stopText = "The source captured before dismissal."
        start(fixture)
        await waitUntil("Recording starts") { fixture.controller.phase == .recording }
        let sessionID = try XCTUnwrap(fixture.coordinator.sessionID)
        fixture.activity.onUnexpectedEnd?(UUID())
        XCTAssertEqual(fixture.controller.phase, .recording)
        fixture.activity.onUnexpectedEnd?(sessionID)
        fixture.activity.onUnexpectedEnd?(sessionID)
        await waitUntil("Dismissal finishes recording") { fixture.controller.phase == .idle }

        XCTAssertEqual(fixture.speech.stopCalls, 1)
        XCTAssertEqual(try fixture.handoff.latest()?.text, fixture.speech.stopText)
        XCTAssertNil(try fixture.sessions.latest())
    }

    func testCancellationDuringActivityPreparationCannotReviveAnOldRecording() async throws {
        let suspended = CrossAppSuspension<Void>()
        defer { suspended.resume(()) }
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        fixture.activity.startOverride = { await suspended.wait() }
        start(fixture)
        await waitUntil("Activity setup waits") { suspended.isWaiting }
        XCTAssertEqual(fixture.controller.phase, .preparing)
        XCTAssertTrue(fixture.speech.isRecording)
        fixture.controller.appDidEnterBackground()
        await waitUntil("Preparation cancellation finishes") { fixture.controller.phase == .idle }
        XCTAssertFalse(fixture.speech.isRecording)
        XCTAssertNil(fixture.coordinator.sessionID)
        XCTAssertNil(try fixture.sessions.latest())

        start(fixture, destination: .app)
        await waitUntil("New recording starts") { fixture.controller.phase == .recording }
        let newStartedAt = fixture.controller.startedAt
        suspended.resume(())
        await waitUntil("Old preparation returns") { suspended.didReturn }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(fixture.controller.phase, .recording)
        XCTAssertEqual(fixture.controller.startedAt, newStartedAt)
        XCTAssertTrue(fixture.speech.isRecording)
        XCTAssertEqual(fixture.speech.cancelCalls, 1)
        XCTAssertNil(try fixture.handoff.latest())
        XCTAssertNil(try fixture.sessions.latest())
        fixture.controller.cancel()
        await waitUntil("Final cleanup finishes") { fixture.controller.phase == .idle }
    }

    func testMicrophoneInterruptionDuringActivityPreparationCannotCreateFalseListeningState() async throws {
        let suspended = CrossAppSuspension<Void>()
        defer { suspended.resume(()) }
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        fixture.activity.startOverride = { await suspended.wait() }
        start(fixture)
        await waitUntil("Activity setup waits after capture begins") { suspended.isWaiting }
        XCTAssertEqual(fixture.controller.phase, .preparing)
        XCTAssertTrue(fixture.speech.isRecording)

        // SpeechService stops its audio engine before reporting an interruption.
        // This can occur while ActivityKit is still cleaning up an old activity.
        fixture.speech.isRecording = false
        fixture.speech.onInterruption?()
        await waitUntil("Interrupted preparation cancels") { fixture.controller.phase == .idle }
        XCTAssertNotNil(fixture.controller.notice)
        XCTAssertFalse(fixture.speech.isRecording)
        XCTAssertEqual(fixture.speech.cancelCalls, 1)
        XCTAssertNil(fixture.coordinator.sessionID)
        XCTAssertNil(try fixture.sessions.latest())
        XCTAssertNil(try fixture.handoff.latest())
        XCTAssertTrue(fixture.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.historyURL.path))

        fixture.activity.startOverride = nil
        start(fixture)
        await waitUntil("A replacement keyboard recording starts") { fixture.controller.phase == .recording }
        let nextSessionID = try XCTUnwrap(fixture.coordinator.sessionID)
        let nextStartedAt = fixture.controller.startedAt
        suspended.resume(())
        await waitUntil("Interrupted activity setup returns") { suspended.didReturn }
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(fixture.controller.phase, .recording)
        XCTAssertEqual(fixture.controller.startedAt, nextStartedAt)
        XCTAssertTrue(fixture.speech.isRecording)
        XCTAssertEqual(fixture.speech.cancelCalls, 1)
        XCTAssertEqual(fixture.coordinator.sessionID, nextSessionID)
        XCTAssertEqual(try fixture.sessions.latest()?.id, nextSessionID)
        XCTAssertEqual(fixture.activity.endedPhases, [.cancelled])
        XCTAssertNil(try fixture.handoff.latest())
        XCTAssertTrue(fixture.store.entries.isEmpty)
        fixture.controller.cancel()
        await waitUntil("Replacement recording cleanup finishes") { fixture.controller.phase == .idle }
    }

    func testCoordinatorDeliversStopAndCompletionDeadlineOnlyOnce() async throws {
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        var stopCalls = 0
        var expirationCalls = 0
        fixture.coordinator.onStop = { stopCalls += 1 }
        fixture.coordinator.onExpiration = { expirationCalls += 1 }
        let sessionID = UUID()
        try await fixture.coordinator.start(sessionID: sessionID)
        let now = Date()
        try fixture.sessions.send(.stop, sessionID: sessionID, now: now)
        fixture.coordinator.poll(now: now)
        fixture.coordinator.poll(now: now, recordingElapsed: KeyboardRecordingSessionStore.recordingLimit)
        // Repeated human controls have new command IDs but still request one stop.
        try fixture.sessions.send(.stop, sessionID: sessionID, now: now)
        fixture.coordinator.poll(now: now)
        XCTAssertEqual(stopCalls, 1)

        await fixture.coordinator.transition(to: .refining)
        fixture.coordinator.poll(completionElapsed: KeyboardRecordingSessionStore.completionAllowance - 1)
        XCTAssertEqual(expirationCalls, 0)
        fixture.coordinator.poll(completionElapsed: KeyboardRecordingSessionStore.completionAllowance)
        fixture.coordinator.poll(completionElapsed: KeyboardRecordingSessionStore.completionAllowance + 1)
        XCTAssertEqual(expirationCalls, 1)
        await fixture.coordinator.end(sessionID: sessionID, phase: .ready, note: nil)
    }

    func testCoordinatorRecordingDeadlineStopsWithoutAnExternalCommand() async throws {
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        var stopCalls = 0
        fixture.coordinator.onStop = { stopCalls += 1 }
        let sessionID = UUID()
        try await fixture.coordinator.start(sessionID: sessionID)
        fixture.coordinator.poll(recordingElapsed: KeyboardRecordingSessionStore.recordingLimit - 1)
        XCTAssertEqual(stopCalls, 0)
        fixture.coordinator.poll(recordingElapsed: KeyboardRecordingSessionStore.recordingLimit)
        fixture.coordinator.poll(recordingElapsed: KeyboardRecordingSessionStore.recordingLimit + 1)
        XCTAssertEqual(stopCalls, 1)
        await fixture.coordinator.end(sessionID: sessionID, phase: .cancelled, note: nil)
    }

    func testDelayedOldActivityEndCannotRemoveReplacementSessionOrPublishForIt() async throws {
        let suspended = CrossAppSuspension<Void>()
        defer { suspended.resume(()) }
        let fixture = CrossAppFixture()
        defer { fixture.removeFiles() }
        let firstID = UUID()
        try await fixture.coordinator.start(sessionID: firstID)
        fixture.activity.endOverride = { await suspended.wait() }
        let ending = Task { await fixture.coordinator.end(sessionID: firstID, phase: .cancelled, note: nil) }
        await waitUntil("Old activity dismissal waits") { suspended.isWaiting }
        XCTAssertNil(fixture.coordinator.sessionID)

        let nextID = UUID()
        try await fixture.coordinator.start(sessionID: nextID)
        suspended.resume(())
        await ending.value
        XCTAssertEqual(fixture.coordinator.sessionID, nextID)
        XCTAssertEqual(try fixture.sessions.latest()?.id, nextID)
        await fixture.coordinator.end(sessionID: firstID, phase: .cancelled, note: nil)
        XCTAssertEqual(try fixture.sessions.latest()?.id, nextID)
        var old = CrossAppFixture.entry("An old result must not use the replacement mailbox.")
        old.id = firstID
        XCTAssertThrowsError(try fixture.coordinator.publish(old))
        XCTAssertNil(try fixture.handoff.latest())

        fixture.activity.endOverride = nil
        await fixture.coordinator.end(sessionID: nextID, phase: .cancelled, note: nil)
        XCTAssertNil(try fixture.sessions.latest())
    }
}

@MainActor
private final class CrossAppFixture {
    let directory: URL
    let historyURL: URL
    let sessions: KeyboardRecordingSessionStore
    let handoff: KeyboardHandoff
    let activity = CrossAppActivity()
    let speech = CrossAppSpeech()
    let store: DictationStore
    let coordinator: KeyboardRecordingCoordinator
    let controller: DictationController

    init(unavailableHandoff: Bool = false, transformation: DictationController.Transformation? = nil) {
        directory = URL.temporaryDirectory.appending(path: "SaysoCrossAppTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        historyURL = directory.appending(path: "history.json")
        sessions = KeyboardRecordingSessionStore(containerURL: directory)
        handoff = KeyboardHandoff(containerURL: unavailableHandoff ? nil : directory)
        store = DictationStore(fileURL: historyURL)
        coordinator = KeyboardRecordingCoordinator(sessions: sessions, handoff: handoff,
                                                    activity: activity, automaticallyPolls: false)
        controller = DictationController(store: store, speech: speech,
            transformation: transformation ?? { text, _, _, _ in text }, keyboardRecording: coordinator)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: directory) }

    static func entry(_ text: String) -> Dictation {
        Dictation(text: text, original: text, mode: .transcript, duration: 2, localeIdentifier: "en-US")
    }
}

@MainActor
private final class CrossAppActivity: RecordingActivityCoordinating {
    var onUnexpectedEnd: ((UUID) -> Void)?
    var startFailure: Error?
    var startOverride: (() async -> Void)?
    var endOverride: (() async -> Void)?
    private(set) var startedIDs: [UUID] = []
    private(set) var updatedPhases: [RecordingActivityAttributes.Phase] = []
    private(set) var endedPhases: [RecordingActivityAttributes.Phase] = []

    func start(sessionID: UUID, startedAt: Date, endsAt: Date) async throws {
        startedIDs.append(sessionID)
        if let startFailure { throw startFailure }
        if let startOverride { await startOverride() }
    }
    func update(phase: RecordingActivityAttributes.Phase, note: String?) async { updatedPhases.append(phase) }
    func end(phase: RecordingActivityAttributes.Phase, note: String?) async {
        endedPhases.append(phase)
        if let endOverride { await endOverride() }
    }
}

@MainActor
private final class CrossAppSpeech: SpeechTranscribing {
    var partialText = ""
    var level = 0.0
    var status = "Ready"
    var isRecording = false
    var onInterruption: (() -> Void)?
    var stopText = "A complete recording."
    var stopOverride: (() async -> String)?
    var cancelOverride: (() async -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var cancelCalls = 0

    func resetTranscript() { partialText = ""; level = 0 }
    func start(localeIdentifier: String, contextualStrings: [String]) async throws { startCalls += 1; isRecording = true }
    func stop() async throws -> String {
        stopCalls += 1
        isRecording = false
        if let stopOverride { return await stopOverride() }
        return stopText
    }
    func cancel() async {
        cancelCalls += 1
        isRecording = false
        if let cancelOverride { await cancelOverride() }
    }
}

@MainActor
private final class CrossAppSuspension<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private(set) var didReturn = false
    var isWaiting: Bool { continuation != nil }

    func wait() async -> Value {
        let result = await withCheckedContinuation { continuation = $0 }
        didReturn = true
        return result
    }
    func resume(_ result: Value) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}

private enum CrossAppFailure: Error { case activityUnavailable }
