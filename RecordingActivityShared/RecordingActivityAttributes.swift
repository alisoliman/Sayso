import ActivityKit
import Foundation

/// Small status-only payload shared by the app and its widget extension.
/// Dictated text and audio never belong in Live Activity content.
nonisolated struct RecordingActivityAttributes: ActivityAttributes, Sendable {
    enum Phase: String, Codable, Hashable, Sendable {
        case listening, finishing, refining, ready, failed, cancelled

        var title: String {
            switch self {
            case .listening: "Recording in Sayso"
            case .finishing: "Finishing your words"
            case .refining: "Refining your text"
            case .ready: "Your text is ready"
            case .failed: "Recording ended"
            case .cancelled: "Recording cancelled"
            }
        }

        var symbol: String {
            switch self {
            case .listening: "waveform"
            case .finishing: "ellipsis"
            case .refining: "sparkles"
            case .ready: "checkmark"
            case .failed: "exclamationmark"
            case .cancelled: "xmark"
            }
        }

        var isTerminal: Bool { self == .ready || self == .failed || self == .cancelled }
    }

    struct ContentState: Codable, Hashable, Sendable {
        let phase: Phase
        /// A short status explanation, never the person's transcript.
        let note: String?
        /// Freezes the elapsed timer when microphone capture finishes.
        let stoppedAt: Date?
        /// The last time the owning app confirmed this session's status.
        /// Optional so a widget can safely render an older activity as stale.
        let confirmedAt: Date?

        init(phase: Phase, note: String?, stoppedAt: Date?, confirmedAt: Date? = nil) {
            self.phase = phase
            self.note = note
            self.stoppedAt = stoppedAt
            self.confirmedAt = confirmedAt
        }
    }

    let sessionID: UUID
    let startedAt: Date
    let endsAt: Date

    static let freshnessLifetime: TimeInterval = 15
    static let recordingURL = URL(string: "sayso://recording")!
}
