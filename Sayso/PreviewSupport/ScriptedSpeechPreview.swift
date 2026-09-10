#if DEBUG
import Foundation
import Observation
import SwiftUI

/// Deterministic UI exercise only. Never selected without both UI-test flags,
/// never included in Release, and never evidence of microphone/model quality.
@MainActor @Observable
final class ScriptedSpeechPreview: SpeechTranscribing {
    var partialText = ""
    var level = 0.0
    var status = ""
    var isRecording = false
    var onInterruption: (() -> Void)?
    @ObservationIgnored private var playback: Task<Void, Never>?
    private let extended: Bool

    static let thought = "Let’s meet tomorrow morning. We can walk by the water, find a quiet café, and talk through the ideas for our next project."
    static let longerThought = """
    I want to make a little more room for the things that matter. A walk before the day begins, a proper lunch away from my desk, and time to write down the ideas that usually disappear before evening.

    For the next project, let’s start with one clear question. Who is this for, and what should feel easier when they use it? We can spend Monday listening, Tuesday sketching, and Wednesday trying something small together.

    There is no need to rush the details. Keep the first version simple enough to understand at a glance. Make the words readable, leave enough space between the controls, and pay attention to what happens when someone makes a mistake.

    Before we share it, I would like to walk through the whole experience on a phone. Start from the beginning, use it with one hand, try a long thought, and make sure everything is still comfortable when the text is larger.

    Finally, send the notes to the team on Friday morning. Include the questions we have not answered, the things we learned, and the next small step. We can decide what to build after everyone has had time to think.
    """

    init(extended: Bool = false) { self.extended = extended }

    func resetTranscript() { partialText = ""; level = 0 }

    func start(localeIdentifier: String, contextualStrings: [String]) async throws {
        status = "Getting ready…"
        try await Task.sleep(for: .milliseconds(300))
        partialText = ""
        isRecording = true
        status = "Listening"
        let words = (extended ? Self.longerThought : Self.thought).split(separator: " ")
        playback = Task {
            for count in stride(from: 5, through: words.count + 4, by: 5) {
                do { try await Task.sleep(for: .milliseconds(extended ? 110 : 500)) } catch { return }
                guard !Task.isCancelled else { return }
                partialText = words.prefix(min(count, words.count)).joined(separator: " ")
                level = 0.15 + Double(count % 7) / 20
            }
        }
    }

    func stop() async throws -> String {
        playback?.cancel()
        playback = nil
        isRecording = false
        level = 0
        let panelTest = ProcessInfo.processInfo.arguments.contains("--keyboard-panel-host")
        try await Task.sleep(for: .milliseconds(panelTest ? 3_000 : 550))
        return partialText
    }

    func cancel() async {
        playback?.cancel()
        playback = nil
        isRecording = false
        level = 0
    }

    func transcribeFile(at url: URL, localeIdentifier: String, contextualStrings: [String]) async throws -> String {
        throw CocoaError(.featureUnsupported)
    }

    static func transform(_ text: String, mode: WritingMode, instructions: String, vocabulary: [String]) async throws -> String {
        // The explicit slow path lets native accessibility tests inspect and
        // cancel refinement without racing the ordinary preview's completion.
        let slow = ProcessInfo.processInfo.arguments.contains("--scripted-slow-refinement")
        try await Task.sleep(for: .milliseconds(slow ? 30_000 : 1500))
        return text
    }
}
/// Keeps an ordinary editable host and the real keyboard extension visible while
/// the audio-free service finishes. This verifies UIKit/IPC, never microphone or
/// operating-system background execution. All launch gates are in SaysoApp.
struct KeyboardPanelPreview: View {
    @Bindable var model: DictationController
    @State private var firstText = ""
    @State private var otherText = ""
    @FocusState private var focusedField: Field?
    private enum Field { case first, other }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Record fixture") {
                    model.start(mode: .transcript, locale: "en-US", instructions: "", vocabulary: "",
                                saveHistory: false, destination: .keyboard)
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("keyboardFixtureRecord")
                Spacer()
                Button("Reset fixture") {
                    focusedField = nil
                    model.cancel()
                    firstText = ""
                    otherText = ""
                    try? KeyboardHandoff().clear()
                }
                .accessibilityIdentifier("keyboardFixtureReset")
            }
            Text(model.speech.partialText.isEmpty ? "Waiting for fixture" : model.speech.partialText)
                .lineLimit(1)
                .accessibilityIdentifier("keyboardFixtureTranscript")
            Text(model.current?.writingStyle?.id ?? model.current?.mode.rawValue ?? "recording")
                .font(.caption)
                .accessibilityIdentifier("keyboardFixtureResultMode")
            TextEditor(text: $firstText)
                .focused($focusedField, equals: .first)
                .frame(minHeight: 60, maxHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                .accessibilityIdentifier("keyboardHostField")
            TextEditor(text: $otherText)
                .focused($focusedField, equals: .other)
                .frame(minHeight: 60, maxHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                .accessibilityIdentifier("keyboardOtherHostField")
            Spacer(minLength: 0)
        }
        .padding()
    }
}
#endif
