import SwiftUI

@main
struct SaysoApp: App {
    @State private var model: DictationController
    @State private var styles: WritingStyleStore
    private let preferences: UserDefaults
    init() {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let storageID = ProcessInfo.processInfo.environment["TEST_STORAGE_ID"] ?? "default"
        let url = testing ? URL.temporaryDirectory.appending(path: "sayso-ui-tests-\(storageID).json") : nil
        preferences = testing ? UserDefaults(suiteName: "Sayso.UITests.\(storageID)")! : .standard
        _styles = State(initialValue: WritingStyleStore(defaults: preferences))
        if testing, ProcessInfo.processInfo.arguments.contains("--scripted-speech") {
            _model = State(initialValue: DictationController(
                store: DictationStore(fileURL: url),
                speech: ScriptedSpeechPreview(extended: ProcessInfo.processInfo.arguments.contains("--scripted-long")),
                transformation: ScriptedSpeechPreview.transform, preferences: preferences))
            return
        }
        #else
        let url: URL? = nil
        preferences = .standard
        _styles = State(initialValue: WritingStyleStore(defaults: preferences))
        #endif
        _model = State(initialValue: DictationController(store: DictationStore(fileURL: url), preferences: preferences))
    }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitesting"),
                   ProcessInfo.processInfo.arguments.contains("--scripted-speech"),
                   ProcessInfo.processInfo.arguments.contains("--keyboard-panel-host") {
                    KeyboardPanelPreview(model: model)
                } else {
                    ContentView(model: model, styles: styles)
                }
                #else
                ContentView(model: model, styles: styles)
                #endif
            }
            .tint(SaysoTheme.accent).defaultAppStorage(preferences)
        }
    }
}
