import AppIntents
import Observation

@MainActor @Observable
final class AppRoute {
    static let shared = AppRoute()
    struct RecordingRequest: Equatable {
        let id: UUID
        let destination: DictationController.Destination
    }
    var recordRequest: RecordingRequest?
    func requestRecording(destination: DictationController.Destination = .app) {
        recordRequest = RecordingRequest(id: UUID(), destination: destination)
    }
}

struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Open Sayso and turn your voice into text on this iPhone.")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor func perform() async throws -> some IntentResult {
        AppRoute.shared.requestRecording()
        return .result()
    }
}

struct StartKeyboardDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictate in Another App"
    static let description = IntentDescription("Start in Sayso, then return to your app. Stop with the Sayso keyboard or Live Activity and insert your text.")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor func perform() async throws -> some IntentResult {
        AppRoute.shared.requestRecording(destination: .keyboard)
        return .result()
    }
}

struct SaysoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDictationIntent(), phrases: ["Dictate with \(.applicationName)", "Start dictation in \(.applicationName)", "Record with \(.applicationName)"], shortTitle: "Start Dictation", systemImageName: "waveform")
        AppShortcut(intent: StartKeyboardDictationIntent(), phrases: ["Keyboard dictation with \(.applicationName)"], shortTitle: "Keyboard Dictation", systemImageName: "keyboard")
    }
    static var shortcutTileColor: ShortcutTileColor { .purple }
}
