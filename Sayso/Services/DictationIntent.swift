import AppIntents
import Observation

@MainActor @Observable
final class AppRoute {
    static let shared = AppRoute()
    var recordRequest: UUID?
    func requestRecording() {
        recordRequest = UUID()
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

struct SaysoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDictationIntent(), phrases: ["Dictate with \(.applicationName)", "Start dictation in \(.applicationName)", "Record with \(.applicationName)"], shortTitle: "Start Dictation", systemImageName: "waveform")
    }
    static var shortcutTileColor: ShortcutTileColor { .purple }
}
