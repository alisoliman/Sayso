import AppIntents
import Foundation

/// LiveActivityIntent executes in the containing app process. These actions
/// only signal an already active session; they never start audio or open the app.
struct StopSaysoRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Sayso recording"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Session") var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { throw RecordingActivityCommandError.invalidSession }
        try KeyboardRecordingSessionStore().send(.stop, sessionID: id)
        return .result()
    }
}

struct CancelSaysoRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Sayso recording"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Session") var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { throw RecordingActivityCommandError.invalidSession }
        try KeyboardRecordingSessionStore().send(.cancel, sessionID: id)
        return .result()
    }
}

private enum RecordingActivityCommandError: LocalizedError {
    case invalidSession
    var errorDescription: String? { "This recording is no longer available." }
}
