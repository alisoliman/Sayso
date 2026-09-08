import SwiftUI

@main
struct SaysoApp: App {
    @State private var model: DictationController
    private let preferences: UserDefaults
    init() {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let storageID = ProcessInfo.processInfo.environment["TEST_STORAGE_ID"] ?? "default"
        let url = testing ? URL.temporaryDirectory.appending(path: "sayso-ui-tests-\(storageID).json") : nil
        preferences = testing ? UserDefaults(suiteName: "Sayso.UITests.\(storageID)")! : .standard
        if testing, ProcessInfo.processInfo.arguments.contains("--scripted-speech") {
            _model = State(initialValue: DictationController(
                store: DictationStore(fileURL: url),
                speech: ScriptedSpeechPreview(extended: ProcessInfo.processInfo.arguments.contains("--scripted-long")),
                transformation: ScriptedSpeechPreview.transform))
            return
        }
        #else
        let url: URL? = nil
        preferences = .standard
        #endif
        _model = State(initialValue: DictationController(store: DictationStore(fileURL: url), preferences: preferences))
    }
    var body: some Scene {
        WindowGroup {
            ContentView(model: model).tint(SaysoTheme.accent).defaultAppStorage(preferences)
        }
    }
}
