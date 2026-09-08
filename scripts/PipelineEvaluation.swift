import AVFoundation
import Foundation
import Speech

/// Synthetic audio, real local host APIs. This is not a microphone or iPhone test.
@main
@MainActor
struct PipelineEvaluation {
    struct Fixture {
        let id: String
        let mode: WritingMode
        let utterance: String
        var customInstructions = ""
    }

    static let fixtures: [Fixture] = [
        .init(id: "clean-cards-correction", mode: .clean,
              utterance: "Um, send 18 invitation cards, no, make that 28. The budget is 140 euros, and we should not order the envelopes yet."),
        .init(id: "clean-workshop-uncertainty", mode: .clean,
              utterance: "Uh, I think the workshop should start a little later. Maybe we can open the doors at ten, but please don't confirm the time until Priya replies."),
        .init(id: "message-library-question", mode: .message,
              utterance: "Hey Jordan, um, the library closes early today. Could you meet me outside the bakery instead? I can be there in about twenty minutes."),
        .init(id: "email-invoice-closing", mode: .email,
              utterance: "Hi Morgan, thanks for sending the updated invoice. I checked the delivery charge this morning and it still includes the returned lamp. Could you send a corrected copy before Friday? Many thanks, Jamie."),
        .init(id: "notes-exhibition-owners", mode: .notes,
              utterance: "For the exhibition, we need to print the labels, check the projector, and count the chairs. Nadia is collecting the framed photographs on Thursday. We have not decided whether to rent another table."),
        .init(id: "custom-two-benefits", mode: .custom,
              utterance: "Um, I prefer the larger notebook because there is more room for diagrams and the pages lie flat on my desk.",
              customInstructions: "Use a warm, natural tone and exactly two short bullet points, one for each benefit.")
    ]

    struct Failure: Encodable {
        let domain: String
        let code: Int
        let description: String
        let underlying: [Failure]
        init(_ error: Error) {
            let nsError = error as NSError
            domain = nsError.domain
            code = nsError.code
            description = error.localizedDescription
            underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? Error).map { [Failure($0)] } ?? []
        }
    }

    struct WordError: Encodable {
        let referenceWords: Int
        let recognizedWords: Int
        let substitutions: Int
        let deletions: Int
        let insertions: Int
        let rate: Double
        let normalization = "Lowercase, curly apostrophe folded to straight, punctuation removed; numeric words and digits are NOT equated."
    }

    struct Result: Encodable {
        let id: String
        let mode: String
        let intendedUtterance: String
        let customInstructions: String
        let startedAt: String
        var finishedAt: String?
        var audioDurationSeconds: Double?
        var synthesisSeconds: Double?
        var speechSeconds: Double?
        var modelSeconds: Double?
        var totalSeconds: Double?
        var recognizedTranscript: String?
        var resultCount: Int?
        var finalResultCount: Int?
        var wordError: WordError?
        var rewrite: String?
        var generationAttempts: Int?
        var failedStage: String?
        var error: Failure?
    }

    struct Report: Encodable {
        let startedAt: String
        var finishedAt: String?
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        let architecture = ProcessInfo.processInfo.environment["SAYSO_EVALUATION_ARCH"] ?? "unknown"
        let sdk = ProcessInfo.processInfo.environment["SAYSO_EVALUATION_SDK"] ?? "unknown"
        let xcode = ProcessInfo.processInfo.environment["SAYSO_EVALUATION_XCODE"] ?? "unknown"
        let intelligenceServiceSHA256 = ProcessInfo.processInfo.environment["SAYSO_INTELLIGENCE_SHA256"] ?? "unknown"
        let platform = "Local macOS host; no iPhone, iOS simulator, microphone capture, or iOS 27 runtime."
        let synthesis = "Installed macOS Samantha en_US voice via /usr/bin/say at 165 words per minute."
        let speechEngine = "SpeechAnalyzer + SpeechTranscriber, timeIndexedProgressiveTranscription; production SpeechTranscriptAccumulator."
        let writingEngine = "Production IntelligenceService.swift; local SystemLanguageModel.default."
        let assetsDownloaded = false
        let contextualVocabulary: [String] = []
        let interpretation = "Six synthetic fixtures run once, sequentially. API completion and raw word error rate are not proof of semantic fidelity or writing usefulness. Manual assessment is separate. Audio is temporary and removed after this run."
        var locale: String?
        var modelAvailable: Bool?
        var setupError: Failure?
        var cases: [Result] = []
    }

    struct Transcript {
        var accumulator = SpeechTranscriptAccumulator()
        var resultCount = 0
        var finalCount = 0
    }

    final class Deadline {
        var exceeded = false
    }

    struct EvaluationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2, arguments[0] == "--output" else {
            fputs("Usage: evaluate-pipeline.sh --output /path/to/report.json\n", stderr)
            exit(2)
        }
        let destination = URL(filePath: arguments[1])
        let directory = FileManager.default.temporaryDirectory.appending(path: "sayso-pipeline-\(UUID().uuidString)", directoryHint: .isDirectory)
        var report = Report(startedAt: timestamp())
        var ownedLocale: Locale?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Listing voices does not request an installation. Refuse to synthesize if this
            // already-installed voice is absent instead of requesting a replacement/download.
            let voices = try runProcess("/usr/bin/say", ["-v", "?"])
            guard voices.split(separator: "\n").contains(where: { $0.hasPrefix("Samantha ") && $0.contains("en_US") }) else {
                throw EvaluationError(message: "Samantha en_US is not installed. No voice download was requested.")
            }
            guard SpeechTranscriber.isAvailable else {
                throw EvaluationError(message: "SpeechTranscriber is unavailable on this Mac.")
            }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
                throw EvaluationError(message: "English (US) is not supported on this Mac.")
            }
            report.locale = locale.identifier
            guard await SpeechTranscriber.installedLocales.contains(locale) else {
                throw EvaluationError(message: "English speech assets are not installed. No download was requested.")
            }
            if try await AssetInventory.reserve(locale: locale) { ownedLocale = locale }
            let checkModule = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            guard await AssetInventory.status(forModules: [checkModule]) == .installed else {
                throw EvaluationError(message: "Required speech assets are not fully installed. No download was requested.")
            }
            let intelligence = IntelligenceService()
            report.modelAvailable = intelligence.isAvailable
            // Production availability errors are recorded per case after speech runs.
            for fixture in fixtures {
                var result = Result(id: fixture.id, mode: fixture.mode.rawValue,
                                    intendedUtterance: fixture.utterance,
                                    customInstructions: fixture.customInstructions, startedAt: timestamp())
                let totalStarted = Date()
                var stage = "synthesis"
                var stageStarted = totalStarted
                do {
                    let sourceURL = directory.appending(path: fixture.id + ".txt")
                    let audioURL = directory.appending(path: fixture.id + ".caf")
                    try fixture.utterance.write(to: sourceURL, atomically: true, encoding: .utf8)
                    _ = try runProcess("/usr/bin/say", ["-v", "Samantha", "-r", "165", "-f", sourceURL.path, "-o", audioURL.path])
                    result.synthesisSeconds = Date().timeIntervalSince(stageStarted)
                    let file = try AVAudioFile(forReading: audioURL)
                    result.audioDurationSeconds = Double(file.length) / file.processingFormat.sampleRate
                    stage = "speech"
                    stageStarted = Date()
                    let transcript = try await recognize(file, locale: locale)
                    result.speechSeconds = Date().timeIntervalSince(stageStarted)
                    result.recognizedTranscript = transcript.accumulator.text
                    result.resultCount = transcript.resultCount
                    result.finalResultCount = transcript.finalCount
                    result.wordError = wordError(reference: fixture.utterance, hypothesis: transcript.accumulator.text)
                    stage = "writing"
                    stageStarted = Date()
                    result.rewrite = try await intelligence.transform(transcript.accumulator.text, mode: fixture.mode,
                                                                     customInstructions: fixture.customInstructions, vocabulary: [])
                    result.modelSeconds = Date().timeIntervalSince(stageStarted)
                    result.generationAttempts = intelligence.lastGenerationAttempts
                } catch {
                    result.failedStage = stage
                    result.error = Failure(error)
                    switch stage {
                    case "synthesis": result.synthesisSeconds = Date().timeIntervalSince(stageStarted)
                    case "speech": result.speechSeconds = Date().timeIntervalSince(stageStarted)
                    default:
                        result.modelSeconds = Date().timeIntervalSince(stageStarted)
                        result.generationAttempts = intelligence.lastGenerationAttempts
                    }
                }
                result.totalSeconds = Date().timeIntervalSince(totalStarted)
                result.finishedAt = timestamp()
                report.cases.append(result)
                // Persist completed cases so a later interruption does not hide earlier errors.
                try write(report, to: destination)
                fputs("\(fixture.id): \(result.error == nil ? "completed" : "failed at " + (result.failedStage ?? "unknown"))\n", stderr)
            }
        } catch { report.setupError = Failure(error) }
        if let ownedLocale { await AssetInventory.release(reservedLocale: ownedLocale) }
        try? FileManager.default.removeItem(at: directory)
        report.finishedAt = timestamp()
        do { try write(report, to: destination) }
        catch { fputs("Could not save report: \(error.localizedDescription)\n", stderr); exit(2) }
        print(destination.path)
        exit(report.setupError != nil ? 2 : report.cases.contains(where: { $0.error != nil }) ? 1 : 0)
    }

    static func recognize(_ file: AVAudioFile, locale: Locale) async throws -> Transcript {
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        let results = Task {
            var transcript = Transcript()
            for try await result in transcriber.results {
                transcript.accumulator.replace(text: result.text, in: result.range)
                transcript.resultCount += 1
                if result.isFinal { transcript.finalCount += 1 }
            }
            return transcript
        }
        let deadline = Deadline()
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            deadline.exceeded = true
            await analyzer.cancelAndFinishNow()
        }
        do {
            guard let lastSample = try await analyzer.analyzeSequence(from: file) else {
                throw EvaluationError(message: "The synthesized fixture contained no audio.")
            }
            try await analyzer.finalizeAndFinish(through: lastSample)
            let result = try await results.value
            timeout.cancel()
            await analyzer.cancelAndFinishNow()
            guard !deadline.exceeded else { throw EvaluationError(message: "Speech analysis exceeded the 60-second deadline.") }
            guard result.finalCount > 0 else { throw EvaluationError(message: "Speech analysis produced no final result.") }
            return result
        } catch {
            timeout.cancel()
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    static func runProcess(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EvaluationError(message: "\(executable) exited with code \(process.terminationStatus).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func wordError(reference: String, hypothesis: String) -> WordError {
        func words(_ text: String) -> [String] {
            let normalized = text.lowercased().replacingOccurrences(of: "’", with: "'")
            return normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        }
        let reference = words(reference), hypothesis = words(hypothesis)
        var costs = Array(repeating: Array(repeating: 0, count: hypothesis.count + 1), count: reference.count + 1)
        for i in 0...reference.count { costs[i][0] = i }
        for j in 0...hypothesis.count { costs[0][j] = j }
        if !reference.isEmpty && !hypothesis.isEmpty {
            for i in 1...reference.count {
                for j in 1...hypothesis.count {
                    costs[i][j] = min(costs[i - 1][j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1),
                                      costs[i - 1][j] + 1, costs[i][j - 1] + 1)
                }
            }
        }
        var i = reference.count, j = hypothesis.count, substitutions = 0, deletions = 0, insertions = 0
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && reference[i - 1] == hypothesis[j - 1] && costs[i][j] == costs[i - 1][j - 1] {
                i -= 1; j -= 1
            } else if i > 0 && j > 0 && costs[i][j] == costs[i - 1][j - 1] + 1 {
                substitutions += 1; i -= 1; j -= 1
            } else if i > 0 && costs[i][j] == costs[i - 1][j] + 1 {
                deletions += 1; i -= 1
            } else { insertions += 1; j -= 1 }
        }
        return WordError(referenceWords: reference.count, recognizedWords: hypothesis.count,
                         substitutions: substitutions, deletions: deletions, insertions: insertions,
                         rate: Double(substitutions + deletions + insertions) / Double(max(1, reference.count)))
    }

    static func timestamp() -> String { ISO8601DateFormatter().string(from: Date()) }

    static func write(_ report: Report, to destination: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: destination, options: .atomic)
    }
}
