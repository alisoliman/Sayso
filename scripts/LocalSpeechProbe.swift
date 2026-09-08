import AVFoundation
import Foundation
import Speech

/// A hardware smoke test, not an accuracy benchmark. Never installs assets.
@main
@MainActor
struct LocalSpeechProbe {
    struct Report: Encodable {
        var platform = "macOS host (not iPhone or iOS simulator)"
        var systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        var engine = "SpeechAnalyzer + SpeechTranscriber"
        var fixture = "macOS say, Samantha voice"
        var status = "skipped"
        var reason: String?
        var locale: String?
        var assetsDownloaded = false
        var expectedText: String?
        var recognizedText: String?
        var resultCount: Int?
        var finalResultCount: Int?
        var elapsedSeconds: Double?
    }

    struct Output {
        var accumulator = SpeechTranscriptAccumulator()
        var resultCount = 0
        var finalCount = 0
    }

    static func main() async {
        var report = Report()
        var ownedLocale: Locale?
        var activeAnalyzer: SpeechAnalyzer?
        var outputTask: Task<Output, Error>?
        var timeoutTask: Task<Void, Never>?
        let started = Date()
        do {
            guard CommandLine.arguments.count == 3 else {
                throw ProbeError("Pass an audio file path and its expected transcript.")
            }
            guard SpeechTranscriber.isAvailable else {
                throw ProbeError("SpeechTranscriber is unavailable on this Mac.")
            }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
                throw ProbeError("English (US) is unsupported on this Mac.")
            }
            report.locale = locale.identifier
            let installed = await SpeechTranscriber.installedLocales
            guard installed.contains(locale) else {
                throw ProbeError("English speech assets are not installed. No download was requested.")
            }
            if try await AssetInventory.reserve(locale: locale) { ownedLocale = locale }
            let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw ProbeError("The required speech assets are not fully installed. No download was requested.")
            }
            let file = try AVAudioFile(forReading: URL(filePath: CommandLine.arguments[1]))
            let analyzer = SpeechAnalyzer(modules: [transcriber],
                                          options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            activeAnalyzer = analyzer
            let results = Task {
                var output = Output()
                for try await result in transcriber.results {
                    output.accumulator.replace(text: result.text, in: result.range)
                    output.resultCount += 1
                    if result.isFinal { output.finalCount += 1 }
                }
                return output
            }
            outputTask = results
            timeoutTask = Task {
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                await analyzer.cancelAndFinishNow()
            }
            if let lastSample = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                throw ProbeError("The generated fixture contained no audio.")
            }
            let output = try await results.value
            report.expectedText = CommandLine.arguments[2]
            report.recognizedText = output.accumulator.text
            report.resultCount = output.resultCount
            report.finalResultCount = output.finalCount
            report.elapsedSeconds = Date().timeIntervalSince(started)
            if normalized(output.accumulator.text) == normalized(CommandLine.arguments[2]), output.finalCount > 0 {
                report.status = "passed"
            } else {
                report.status = "mismatch"
                report.reason = "The recognized words differ from the fixture. Review the output; one synthetic fixture does not establish transcription accuracy."
            }
        } catch {
            report.reason = error.localizedDescription
            if activeAnalyzer != nil { report.status = "failed" }
        }
        timeoutTask?.cancel()
        outputTask?.cancel()
        await activeAnalyzer?.cancelAndFinishNow()
        if let ownedLocale { await AssetInventory.release(reservedLocale: ownedLocale) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(report) { print(String(decoding: data, as: UTF8.self)) }
    }

    static func normalized(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    struct ProbeError: LocalizedError {
        let description: String
        init(_ description: String) { self.description = description }
        var errorDescription: String? { description }
    }
}
