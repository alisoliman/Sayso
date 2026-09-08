#if DEBUG
import Foundation
import Observation

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
        try await Task.sleep(for: .milliseconds(550))
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
#endif
