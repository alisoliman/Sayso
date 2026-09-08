import Foundation

/// Coordinates explicit cross-app recording. The audio service remains the sole
/// microphone owner; this object publishes status and receives stop/discard only.
@MainActor
final class KeyboardRecordingCoordinator {
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onExpiration: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var onCheckpoint: (() -> Void)?
    private(set) var sessionID: UUID?
    private(set) var publicationCommitted = false
    private let sessions: KeyboardRecordingSessionStore
    private let handoff: KeyboardHandoff
    private let activity: any RecordingActivityCoordinating
    private let automaticallyPolls: Bool
    private var polling: Task<Void, Never>?
    private var activityRefresh: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var lastActivityHeartbeat = Date.distantPast
    private var beganAt: ContinuousClock.Instant?
    private var completionBeganAt: ContinuousClock.Instant?
    private var phase = KeyboardRecordingSessionStore.Phase.recording
    private var lastCommandID: UUID?
    private var lastHeartbeat = Date.distantPast
    private var lastCheckpoint = Date.distantPast
    private var receivesControls = false
    private var requestedStop = false
    private var requestedExpiration = false

    init(sessions: KeyboardRecordingSessionStore = .init(), handoff: KeyboardHandoff = .init(),
         activity: (any RecordingActivityCoordinating)? = nil, automaticallyPolls: Bool = true) {
        self.sessions = sessions
        self.handoff = handoff
        self.activity = activity ?? RecordingActivityCoordinator()
        self.automaticallyPolls = automaticallyPolls
        self.activity.onUnexpectedEnd = { [weak self] id in
            guard let self, self.sessionID == id else { return }
            if self.phase == .recording { self.requestStop() }
            else { self.onExpiration?() }
        }
    }

    func start(sessionID id: UUID, now: Date = Date()) async throws {
        guard sessionID == nil else { throw KeyboardRecordingSessionStore.SessionError.noActiveSession }
        sessionID = id
        publicationCommitted = false
        receivesControls = true
        phase = .recording
        lastCommandID = nil
        requestedStop = false
        requestedExpiration = false
        beganAt = ContinuousClock.now
        completionBeganAt = nil
        lastActivityHeartbeat = now
        refreshGeneration = UUID()
        do {
            try await activity.start(sessionID: id, startedAt: now,
                                     endsAt: now.addingTimeInterval(KeyboardRecordingSessionStore.recordingLimit))
            try Task.checkCancellation()
            guard sessionID == id else { throw CancellationError() }
            // Choosing this destination explicitly replaces the previously shared result.
            try handoff.clear()
            try sessions.begin(sessionID: id, now: now)
            lastHeartbeat = now
            lastCheckpoint = now
            if automaticallyPolls {
                polling = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                        guard let self, self.sessionID == id else { return }
                        self.poll()
                    }
                }
            }
        } catch {
            if sessionID == id { await end(sessionID: id, phase: .failed, note: nil) }
            throw error
        }
    }

    func transition(to next: KeyboardRecordingSessionStore.Phase) async {
        guard let id = sessionID else { return }
        phase = next
        cancelActivityRefresh()
        lastActivityHeartbeat = Date()
        if next != .recording, completionBeganAt == nil { completionBeganAt = ContinuousClock.now }
        do { try sessions.update(sessionID: id, phase: next) }
        catch { onFailure?(error); return }
        await activity.update(phase: next == .recording ? .listening : next == .finishing ? .finishing : .refining)
    }

    // Time overrides let tests verify deadlines without keeping a microphone or
    // test process running for ten minutes. Production uses a monotonic clock.
    func poll(now: Date = Date(), recordingElapsed: TimeInterval? = nil, completionElapsed: TimeInterval? = nil) {
        guard let id = sessionID, receivesControls else { return }
        do {
            if let command = try sessions.command(sessionID: id, after: lastCommandID, now: now) {
                lastCommandID = command.id
                switch command.action {
                case .stop: requestStop()
                case .cancel: onCancel?(); return
                }
            }
            let elapsed = recordingElapsed ?? beganAt.map { seconds($0.duration(to: .now)) } ?? 0
            if phase == .recording, elapsed >= KeyboardRecordingSessionStore.recordingLimit { requestStop() }
            let finishingTime = completionElapsed ?? completionBeganAt.map { seconds($0.duration(to: .now)) } ?? 0
            if phase != .recording, finishingTime >= KeyboardRecordingSessionStore.completionAllowance, !requestedExpiration {
                requestedExpiration = true
                onExpiration?()
                return
            }
            if now.timeIntervalSince(lastHeartbeat) >= 1 {
                try sessions.update(sessionID: id, phase: phase, now: now)
                lastHeartbeat = now
            }
            if now.timeIntervalSince(lastActivityHeartbeat) >= 5, activityRefresh == nil {
                refreshActivity(sessionID: id, now: now)
            }
            if phase == .recording, now.timeIntervalSince(lastCheckpoint) >= 5 {
                lastCheckpoint = now
                onCheckpoint?()
            }
        } catch { onFailure?(error) }
    }

    func quiesce(sessionID id: UUID) {
        guard sessionID == id else { return }
        receivesControls = false
        polling?.cancel(); polling = nil
        cancelActivityRefresh()
    }

    @discardableResult
    func publish(_ entry: Dictation) throws -> Bool {
        guard sessionID == entry.id else { throw KeyboardRecordingSessionStore.SessionError.noActiveSession }
        return try sessions.complete(sessionID: entry.id) {
            try handoff.publish(text: entry.text, id: entry.id)
            publicationCommitted = true
        }
    }

    func end(sessionID id: UUID, phase terminal: RecordingActivityAttributes.Phase, note: String?) async {
        guard sessionID == id else { return }
        sessionID = nil
        receivesControls = false
        polling?.cancel(); polling = nil
        cancelActivityRefresh()
        beganAt = nil; completionBeganAt = nil
        do { try sessions.end(sessionID: id) }
        catch { onFailure?(error) }
        await activity.end(phase: terminal, note: note)
    }

    private func refreshActivity(sessionID id: UUID, now: Date) {
        let token = UUID()
        refreshGeneration = token
        lastActivityHeartbeat = now
        let expectedPhase = phase
        activityRefresh = Task { [weak self] in
            guard let self else { return }
            defer { if self.refreshGeneration == token { self.activityRefresh = nil } }
            guard !Task.isCancelled, self.sessionID == id, self.receivesControls,
                  self.phase == expectedPhase else { return }
            let displayPhase: RecordingActivityAttributes.Phase = expectedPhase == .recording ? .listening : expectedPhase == .finishing ? .finishing : .refining
            await self.activity.update(phase: displayPhase)
        }
    }

    private func cancelActivityRefresh() {
        refreshGeneration = UUID()
        activityRefresh?.cancel(); activityRefresh = nil
    }

    private func requestStop() {
        guard phase == .recording, !requestedStop else { return }
        requestedStop = true
        onStop?()
    }

    private func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
