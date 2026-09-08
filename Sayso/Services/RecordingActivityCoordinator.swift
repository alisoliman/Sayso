import ActivityKit
import Foundation
import UIKit

@MainActor
protocol RecordingActivityCoordinating: AnyObject {
    var onUnexpectedEnd: ((UUID) -> Void)? { get set }
    func start(sessionID: UUID, startedAt: Date, endsAt: Date) async throws
    func update(phase: RecordingActivityAttributes.Phase, note: String?) async
    func end(phase: RecordingActivityAttributes.Phase, note: String?) async
}

extension RecordingActivityCoordinating {
    func update(phase: RecordingActivityAttributes.Phase) async { await update(phase: phase, note: nil) }
    func end() async { await end(phase: .ready, note: nil) }
}

/// Owns one visible system activity; it does not activate or retain the microphone.
@MainActor
final class RecordingActivityCoordinator: RecordingActivityCoordinating {
    typealias Phase = RecordingActivityAttributes.Phase
    var onUnexpectedEnd: ((UUID) -> Void)?

    private let startupTask: Task<Void, Never>
    private var activity: Activity<RecordingActivityAttributes>?
    private var contentState: RecordingActivityAttributes.ContentState?
    private var stateTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var generation = UUID()
    private var isStarting = false

    init() {
        // Snapshot synchronously: deferred cleanup must never discover and erase
        // an activity created later by this coordinator's first start.
        let orphaned = Activity<RecordingActivityAttributes>.activities
        startupTask = Task {
            for previous in orphaned {
                await previous.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    enum ActivityError: LocalizedError {
        case disabled, alreadyActive, invalidInterval, foregroundRequired
        var errorDescription: String? {
            switch self {
            case .disabled:
                "Allow Live Activities for Sayso in Settings to record while using another app."
            case .alreadyActive:
                "Finish the current recording before starting another."
            case .invalidInterval:
                "The recording’s time limit couldn’t be prepared. Try again in Sayso."
            case .foregroundRequired:
                "Open Sayso to begin recording, then return to the app you’re writing in."
            }
        }
    }

    func start(sessionID: UUID, startedAt: Date, endsAt: Date) async throws {
        guard activity == nil, !isStarting else { throw ActivityError.alreadyActive }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw ActivityError.disabled }
        guard UIApplication.shared.applicationState == .active else { throw ActivityError.foregroundRequired }
        let duration = endsAt.timeIntervalSince(startedAt)
        guard startedAt.timeIntervalSince1970.isFinite, endsAt.timeIntervalSince1970.isFinite,
              duration > 0, duration <= 600, endsAt > Date() else { throw ActivityError.invalidInterval }

        let token = UUID()
        generation = token
        isStarting = true
        defer { if generation == token { isStarting = false } }
        await startupTask.value
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw ActivityError.disabled }
        guard UIApplication.shared.applicationState == .active else { throw ActivityError.foregroundRequired }
        guard endsAt > Date() else { throw ActivityError.invalidInterval }

        let attributes = RecordingActivityAttributes(sessionID: sessionID, startedAt: startedAt, endsAt: endsAt)
        let now = Date()
        let state = RecordingActivityAttributes.ContentState(phase: .listening, note: nil, stoppedAt: nil, confirmedAt: now)
        let staleDate = min(endsAt, now.addingTimeInterval(RecordingActivityAttributes.freshnessLifetime))
        let created = try Activity.request(attributes: attributes,
                                          content: ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100),
                                          pushType: nil)
        activity = created
        contentState = state
        observe(created)
    }

    func update(phase: Phase, note: String? = nil) async {
        guard let activity else { return }
        let now = Date()
        let stoppedAt = contentState?.stoppedAt ?? (phase == .listening ? nil : min(now, activity.attributes.endsAt))
        let state = RecordingActivityAttributes.ContentState(phase: phase, note: statusNote(note), stoppedAt: stoppedAt, confirmedAt: now)
        contentState = state
        let freshUntil = now.addingTimeInterval(RecordingActivityAttributes.freshnessLifetime)
        let staleDate: Date? = phase.isTerminal ? nil : (phase == .listening ? min(activity.attributes.endsAt, freshUntil) : freshUntil)
        await activity.update(ActivityContent(state: state, staleDate: staleDate, relevanceScore: phase.isTerminal ? 25 : 100),
                              timestamp: now)
    }

    func end(phase: Phase = .ready, note: String? = nil) async {
        generation = UUID()
        isStarting = false
        stateTask?.cancel(); stateTask = nil
        authorizationTask?.cancel(); authorizationTask = nil
        guard let ending = activity else { return }
        let now = Date()
        let state = RecordingActivityAttributes.ContentState(
            phase: phase, note: statusNote(note),
            stoppedAt: contentState?.stoppedAt ?? min(now, ending.attributes.endsAt),
            confirmedAt: now
        )
        // Clear ownership before awaiting, so this completion cannot erase a
        // subsequent session started after the old one was deliberately ended.
        activity = nil
        contentState = nil
        let dismissal: ActivityUIDismissalPolicy = phase == .cancelled ? .immediate : .after(now.addingTimeInterval(8))
        await ending.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: dismissal, timestamp: now)
    }

    private func observe(_ observed: Activity<RecordingActivityAttributes>) {
        stateTask = Task { [weak self] in
            for await state in observed.activityStateUpdates {
                guard !Task.isCancelled, let self, self.activity?.id == observed.id else { return }
                if state == .stale {
                    // A queued stale event may belong to the snapshot preceding
                    // a heartbeat. Consult ActivityKit's current published state,
                    // not our locally attempted update, before stopping capture.
                    guard observed.activityState == .stale,
                          let staleDate = observed.content.staleDate,
                          staleDate <= Date() else { continue }
                    self.activityBecameUnavailable(observed)
                    return
                }
                if state == .dismissed || state == .ended {
                    self.activityBecameUnavailable(observed)
                    return
                }
            }
        }
        authorizationTask = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard !Task.isCancelled, let self, self.activity?.id == observed.id else { return }
                if !enabled {
                    self.activityBecameUnavailable(observed)
                    return
                }
            }
        }
    }

    private func activityBecameUnavailable(_ observed: Activity<RecordingActivityAttributes>) {
        guard activity?.id == observed.id else { return }
        activity = nil
        contentState = nil
        stateTask?.cancel(); stateTask = nil
        authorizationTask?.cancel(); authorizationTask = nil
        onUnexpectedEnd?(observed.attributes.sessionID)
        Task { await observed.end(nil, dismissalPolicy: .immediate) }
    }

    private func statusNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(120))
    }
}
