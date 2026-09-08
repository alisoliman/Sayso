import XCTest
@testable import Sayso

final class KeyboardRecordingSessionTests: XCTestCase {
    private var container: URL!
    private var store: KeyboardRecordingSessionStore!
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        container = URL.temporaryDirectory.appending(path: "SaysoRecordingSessionTests-\(UUID().uuidString)")
        store = KeyboardRecordingSessionStore(containerURL: container)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: container.path) {
            try FileManager.default.removeItem(at: container)
        }
    }

    func testReadOnlyStatusDoesNotCreateFilesAndPublicationContainsMetadataOnly() throws {
        XCTAssertNil(try store.latest(now: date))
        XCTAssertNil(try store.command(sessionID: UUID(), after: nil, now: date))
        XCTAssertFalse(FileManager.default.fileExists(atPath: container.path))
        let id = UUID()
        let session = try store.begin(sessionID: id, now: date)
        XCTAssertEqual(try store.latest(now: date), session)
        XCTAssertNil(try store.command(sessionID: id, after: nil, now: date), "Polling before the first command is normal")
        XCTAssertEqual(session.recordingEndsAt.timeIntervalSince(session.startedAt), 600)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "id", "startedAt", "recordingEndsAt", "updatedAt", "phase"])
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testLeaseRejectsFutureAndExpiredStatusWithoutDeletingOrResurrectingIt() throws {
        let id = UUID()
        let session = try store.begin(sessionID: id, now: date)
        XCTAssertNil(try store.latest(now: date.addingTimeInterval(-1)))
        XCTAssertNotNil(try store.latest(now: date.addingTimeInterval(15)))
        XCTAssertNil(try store.latest(now: date.addingTimeInterval(15.001)))
        XCTAssertThrowsError(try store.send(.stop, sessionID: id, now: date.addingTimeInterval(16)))
        XCTAssertThrowsError(try store.update(sessionID: id, phase: .recording, now: date.addingTimeInterval(16)))
        XCTAssertEqual(try JSONDecoder().decode(KeyboardRecordingSessionStore.Session.self,
                                              from: Data(contentsOf: sessionURL)), session)
    }

    func testHeartbeatAndPhasesAreMonotonicAndCompletionHasAHardDeadline() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        try store.update(sessionID: id, phase: .recording, now: date.addingTimeInterval(10))
        XCTAssertThrowsError(try store.update(sessionID: id, phase: .recording, now: date.addingTimeInterval(9)))
        try store.update(sessionID: id, phase: .finishing, now: date.addingTimeInterval(11))
        XCTAssertThrowsError(try store.update(sessionID: id, phase: .recording, now: date.addingTimeInterval(12)))
        try store.update(sessionID: id, phase: .refining, now: date.addingTimeInterval(12))
        XCTAssertThrowsError(try store.update(sessionID: id, phase: .finishing, now: date.addingTimeInterval(13)))
        // Keep the lease alive; the absolute maximum still cannot be extended.
        for offset in stride(from: 22, through: 652, by: 10) {
            try store.update(sessionID: id, phase: .refining, now: date.addingTimeInterval(Double(offset)))
        }
        XCTAssertNotNil(try store.latest(now: date.addingTimeInterval(660)))
        XCTAssertNil(try store.latest(now: date.addingTimeInterval(660.001)))
        XCTAssertThrowsError(try store.update(sessionID: id, phase: .refining, now: date.addingTimeInterval(661)))
    }

    func testCommandsAreScopedAcknowledgedAndDoNotDeleteNewerCommands() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        XCTAssertThrowsError(try store.send(.stop, sessionID: UUID(), now: date))
        try store.send(.stop, sessionID: id, now: date.addingTimeInterval(1))
        let first = try XCTUnwrap(store.command(sessionID: id, after: nil, now: date.addingTimeInterval(1)))
        XCTAssertEqual(first.action, .stop)
        XCTAssertNil(try store.command(sessionID: UUID(), after: nil, now: date.addingTimeInterval(1)))
        XCTAssertNil(try store.command(sessionID: id, after: first.id, now: date.addingTimeInterval(1)))
        try store.send(.cancel, sessionID: id, now: date.addingTimeInterval(2))
        let second = try XCTUnwrap(store.command(sessionID: id, after: first.id, now: date.addingTimeInterval(2)))
        XCTAssertEqual(second.action, .cancel)
        XCTAssertNotEqual(first.id, second.id)
        try store.send(.stop, sessionID: id, now: date.addingTimeInterval(3))
        XCTAssertEqual(try store.command(sessionID: id, after: first.id, now: date.addingTimeInterval(3)), second)
        XCTAssertNil(try store.command(sessionID: id, after: second.id, now: date.addingTimeInterval(3)))
    }

    func testStopDuringCompletionIsIgnoredButCancelRemainsAvailable() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        try store.update(sessionID: id, phase: .finishing, now: date.addingTimeInterval(1))
        try store.send(.stop, sessionID: id, now: date.addingTimeInterval(2))
        XCTAssertNil(try store.command(sessionID: id, after: nil, now: date.addingTimeInterval(2)))
        try store.send(.cancel, sessionID: id, now: date.addingTimeInterval(3))
        XCTAssertEqual(try store.command(sessionID: id, after: nil, now: date.addingTimeInterval(3))?.action, .cancel)
    }

    func testReplacingSessionClearsOldCommandAndDelayedCleanupCannotEndReplacement() throws {
        let oldID = UUID(), newID = UUID()
        try store.begin(sessionID: oldID, now: date)
        try store.send(.cancel, sessionID: oldID, now: date)
        try store.begin(sessionID: newID, now: date.addingTimeInterval(1))
        XCTAssertNil(try store.command(sessionID: newID, after: nil, now: date.addingTimeInterval(1)))
        XCTAssertThrowsError(try store.send(.cancel, sessionID: oldID, now: date.addingTimeInterval(1)))
        XCTAssertThrowsError(try store.update(sessionID: oldID, phase: .finishing, now: date.addingTimeInterval(1)))
        try store.send(.stop, sessionID: newID, now: date.addingTimeInterval(2))
        try store.end(sessionID: oldID)
        XCTAssertEqual(try store.latest(now: date.addingTimeInterval(2))?.id, newID)
        XCTAssertEqual(try store.command(sessionID: newID, after: nil, now: date.addingTimeInterval(2))?.action, .stop)
        try store.end(sessionID: newID)
        try store.end(sessionID: newID)
        XCTAssertNil(try store.latest(now: date.addingTimeInterval(2)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandURL.path))
    }

    func testCommandMustBelongToLiveSessionAndFitItsTimeWindow() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        func inject(_ createdAt: Date, sessionID: UUID = id, version: Int = 1,
                    action: KeyboardRecordingSessionStore.Action = .stop) throws {
            let command = KeyboardRecordingSessionStore.Command(version: version, id: UUID(), sessionID: sessionID,
                                                               action: action, createdAt: createdAt)
            try JSONEncoder().encode(command).write(to: commandURL)
        }
        for action in [KeyboardRecordingSessionStore.Action.stop, .cancel] {
            try inject(date.addingTimeInterval(-1), action: action)
            XCTAssertNil(try store.command(sessionID: id, after: nil, now: date))
            try inject(date.addingTimeInterval(1), action: action)
            XCTAssertNil(try store.command(sessionID: id, after: nil, now: date))
            try inject(date, sessionID: UUID(), action: action)
            XCTAssertNil(try store.command(sessionID: id, after: nil, now: date))
            try inject(date, version: 2, action: action)
            XCTAssertThrowsError(try store.command(sessionID: id, after: nil, now: date))
        }
        try inject(date)
        try store.update(sessionID: id, phase: .recording, now: date.addingTimeInterval(10))
        XCTAssertNil(try store.command(sessionID: id, after: nil, now: date.addingTimeInterval(16)), "An old Stop expires even with a live heartbeat")
        try inject(date.addingTimeInterval(24))
        XCTAssertNil(try store.command(sessionID: id, after: nil, now: date.addingTimeInterval(26)), "Fresh commands cannot revive an expired session")
    }

    func testMalformedUnsupportedOversizedAndTamperedFilesAreRejectedWithoutReadMutation() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        let broken = Data("{broken".utf8)
        try broken.write(to: sessionURL)
        XCTAssertThrowsError(try store.latest(now: date))
        XCTAssertEqual(try Data(contentsOf: sessionURL), broken)
        for version in [1, 2] {
            let invalid = KeyboardRecordingSessionStore.Session(version: version, id: id, startedAt: date,
                                                                recordingEndsAt: date.addingTimeInterval(version == 1 ? 601 : 600),
                                                                updatedAt: date, phase: .recording)
            try JSONEncoder().encode(invalid).write(to: sessionURL)
            XCTAssertThrowsError(try store.latest(now: date))
        }
        try Data(repeating: 32, count: 8_193).write(to: sessionURL)
        XCTAssertThrowsError(try store.latest(now: date))
        try store.begin(sessionID: id, now: date)
        try broken.write(to: commandURL)
        XCTAssertThrowsError(try store.command(sessionID: id, after: nil, now: date))
        XCTAssertEqual(try Data(contentsOf: commandURL), broken)
        // Explicit new recording safely replaces corrupted ephemeral metadata.
        try store.begin(sessionID: UUID(), now: date)
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandURL.path))
        XCTAssertThrowsError(try KeyboardRecordingSessionStore(containerURL: nil).begin(sessionID: UUID(), now: date))
        XCTAssertThrowsError(try KeyboardRecordingSessionStore(containerURL: nil).latest(now: date))
    }

    func testConcurrentIndependentSendersCannotReplaceCancelWithStop() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        let container = try XCTUnwrap(container)
        let now = date
        // Independent store instances model keyboard and app intent writers.
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            let sender = KeyboardRecordingSessionStore(containerURL: container)
            do { try sender.send(index == 0 ? .cancel : .stop, sessionID: id, now: now) }
            catch { XCTFail("Concurrent command should succeed: \(error)") }
        }
        XCTAssertEqual(try store.command(sessionID: id, after: nil, now: date)?.action, .cancel)
    }

    func testPendingCancelPreventsCompletionAndRemovesOwnedMetadata() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        try store.send(.cancel, sessionID: id, now: date.addingTimeInterval(1))
        var committed = false
        XCTAssertFalse(try store.complete(sessionID: id, now: date.addingTimeInterval(2)) { committed = true })
        XCTAssertFalse(committed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandURL.path))
        XCTAssertThrowsError(try store.send(.cancel, sessionID: id, now: date.addingTimeInterval(2)))
    }

    func testCompletionAllowsExpiredLeaseWithoutRevivingSendersAndKeepsAcceptedCancelTerminal() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        try store.send(.cancel, sessionID: id, now: date.addingTimeInterval(14))
        // Lease expired at 15 seconds, but this submitted Cancel remains fresh.
        XCTAssertThrowsError(try store.send(.cancel, sessionID: id, now: date.addingTimeInterval(16)))
        XCTAssertFalse(try store.complete(sessionID: id, now: date.addingTimeInterval(16)) {
            XCTFail("A valid cancellation must survive expiry of its session's heartbeat")
        })
        try store.begin(sessionID: id, now: date)
        try store.send(.cancel, sessionID: id, now: date)
        var commits = 0
        XCTAssertFalse(try store.complete(sessionID: id, now: date.addingTimeInterval(700)) { commits += 1 })
        XCTAssertEqual(commits, 0, "An accepted Cancel must still prevent publication after a long host suspension")
        XCTAssertThrowsError(try store.send(.cancel, sessionID: id, now: date.addingTimeInterval(700)))
    }

    func testStopCannotOverwriteAcceptedCancelAfterItsOriginalCommandWindow() throws {
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        try store.send(.cancel, sessionID: id, now: date)
        let original = try XCTUnwrap(store.command(sessionID: id, after: nil, now: date))
        try store.update(sessionID: id, phase: .recording, now: date.addingTimeInterval(10))
        try store.update(sessionID: id, phase: .recording, now: date.addingTimeInterval(20))
        try store.send(.stop, sessionID: id, now: date.addingTimeInterval(20))
        XCTAssertEqual(try store.command(sessionID: id, after: nil, now: date.addingTimeInterval(20)), original)
        XCTAssertNil(try store.command(sessionID: id, after: original.id, now: date.addingTimeInterval(20)))
        XCTAssertFalse(try store.complete(sessionID: id, now: date.addingTimeInterval(700)) {
            XCTFail("A delayed Stop must not erase an accepted cancellation")
        })
        let nextID = UUID()
        try store.begin(sessionID: nextID, now: date.addingTimeInterval(701))
        XCTAssertTrue(try store.complete(sessionID: nextID, now: date.addingTimeInterval(701)) {},
                      "The previous recording's cancellation cannot affect a new UUID")
    }

    func testFailedCompletionPreservesSessionAndCommandForExplicitCleanup() throws {
        enum Failure: Error { case write }
        let id = UUID()
        try store.begin(sessionID: id, now: date)
        try store.send(.stop, sessionID: id, now: date)
        let originalSession = try Data(contentsOf: sessionURL)
        let originalCommand = try Data(contentsOf: commandURL)
        XCTAssertThrowsError(try store.complete(sessionID: id, now: date) { throw Failure.write })
        XCTAssertEqual(try Data(contentsOf: sessionURL), originalSession)
        XCTAssertEqual(try Data(contentsOf: commandURL), originalCommand)
        XCTAssertTrue(try store.complete(sessionID: id, now: date) {})
        XCTAssertNil(try store.latest(now: date))
    }

    func testOldCompletionCannotCommitOrRemoveReplacement() throws {
        let oldID = UUID(), newID = UUID()
        try store.begin(sessionID: oldID, now: date)
        try store.begin(sessionID: newID, now: date)
        try store.send(.cancel, sessionID: newID, now: date)
        let originalSession = try Data(contentsOf: sessionURL)
        let originalCommand = try Data(contentsOf: commandURL)
        XCTAssertThrowsError(try store.complete(sessionID: oldID, now: date) { XCTFail("Must never commit an old session") })
        XCTAssertEqual(try Data(contentsOf: sessionURL), originalSession)
        XCTAssertEqual(try Data(contentsOf: commandURL), originalCommand)
    }

    func testRacingCancelAndCompletionHaveOneUnambiguousCommittedBoundary() throws {
        let container = try XCTUnwrap(container)
        let now = date
        for _ in 0..<30 {
            let id = UUID()
            try store.begin(sessionID: id, now: now)
            let outcome = CompletionRaceOutcome()
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                let participant = KeyboardRecordingSessionStore(containerURL: container)
                if index == 0 {
                    do {
                        try participant.send(.cancel, sessionID: id, now: now)
                        outcome.recordCancellation(accepted: true)
                    } catch KeyboardRecordingSessionStore.SessionError.noActiveSession {
                        outcome.recordCancellation(accepted: false)
                    } catch { XCTFail("Unexpected cancellation failure: \(error)") }
                } else {
                    do {
                        let committed = try participant.complete(sessionID: id, now: now) { outcome.recordCommit() }
                        outcome.recordCompletion(committed)
                    } catch { XCTFail("Completion must settle the owned session: \(error)") }
                }
            }
            let result = outcome.snapshot()
            let accepted = try XCTUnwrap(result.cancelAccepted)
            XCTAssertEqual(result.completed, !accepted)
            XCTAssertEqual(result.commits, accepted ? 0 : 1,
                           "An accepted pre-commit Cancel must prevent publication; a post-commit Cancel must fail")
            XCTAssertNil(try store.latest(now: now))
        }
    }

    private var directory: URL { container.appending(path: "Recording") }
    private var sessionURL: URL { directory.appending(path: "session.json") }
    private var commandURL: URL { directory.appending(path: "command.json") }
}

private final class CompletionRaceOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelAccepted: Bool?
    private var completed: Bool?
    private var commits = 0

    func recordCancellation(accepted: Bool) { lock.withLock { cancelAccepted = accepted } }
    func recordCompletion(_ value: Bool) { lock.withLock { completed = value } }
    func recordCommit() { lock.withLock { commits += 1 } }
    func snapshot() -> (cancelAccepted: Bool?, completed: Bool?, commits: Int) {
        lock.withLock { (cancelAccepted, completed, commits) }
    }
}
