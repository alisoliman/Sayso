import AVFoundation
import CoreMedia
import CryptoKit
import Foundation
import Speech
import XCTest
@testable import Sayso

/// Explicit physical-device diagnostic; never opens a microphone or DictationStore.
/// The bundled English recording is generated speech, not a user's recording.
@MainActor
final class SpeechRecognitionIntegrationTests: XCTestCase {
    private static let fixtureSHA256 = "6cf42cebb9e453ae7f92b7c00fbfd365b479bcb0faf53d8894a5f28dbdfc0f1c"
    private static let utterance = "Today we are testing local speech recognition. The blue notebook is on the table. Please send the meeting notes tomorrow morning."

    func testSyntheticAudioThroughProductionConverterOnPhysicalDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Speech model probe requires a physical iPhone; simulator checks cannot establish recognition quality.")
        #else
        guard ProcessInfo.processInfo.environment["SAYSO_RUN_DEVICE_SPEECH_PROBE"] == "1" else {
            throw XCTSkip("Opt in with SAYSO_RUN_DEVICE_SPEECH_PROBE=1 in the test host environment.")
        }
        // Synchronized test groups can preserve resource folders or flatten their
        // resource URLs. Both lookups remain inside this test bundle, never app data.
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource: "DeviceSpeechEnglish", withExtension: "wav", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "DeviceSpeechEnglish", withExtension: "wav"), "Synthetic fixture missing from SaysoTests resources.")
        let bytes = try Data(contentsOf: fixture)
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), Self.fixtureSHA256)
        let audio = try AVAudioFile(forReading: fixture)
        XCTAssertEqual(audio.processingFormat.sampleRate, 48_000)
        XCTAssertEqual(audio.processingFormat.channelCount, 1)
        XCTAssertGreaterThan(audio.length, 0)
        var report = ProbeReport(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                 fixtureSHA256: Self.fixtureSHA256, syntheticUtterance: Self.utterance,
                                 fixtureFrames: audio.length,
                                 fixtureDurationSeconds: Double(audio.length) / audio.processingFormat.sampleRate)
        let streamed = StreamedProbe()
        let streamedStarted = Date()
        do {
            let transcript = try await bounded(operation: {
                try await streamed.recognize(fixture)
            }, cancel: { await streamed.cancel() })
            streamed.report.transcript = transcript
            streamed.report.completed = true
        } catch { streamed.report.error = ErrorReport(error) }
        streamed.report.elapsedSeconds = Date().timeIntervalSince(streamedStarted)
        streamed.report.nonempty = !(streamed.report.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        await streamed.cancel()
        report.paths.append(streamed.report)
        try attach(report, name: "Device-Speech-Probe-Streaming")
        XCTAssertTrue(streamed.report.completed && streamed.report.nonempty, "Production-converter streaming failed or returned no words; inspect the synthetic comparison attachment.")
        XCTAssertGreaterThan(streamed.report.finalResultCount ?? 0, 0, "Streamed recognition published no final result.")
        XCTAssertEqual(streamed.report.convertedDurationSeconds ?? -1, report.fixtureDurationSeconds, accuracy: 0.02,
                       "The converter path must consume the complete fixture, including its tail.")
        #endif
    }

    private func attach(_ report: ProbeReport, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = String(decoding: try encoder.encode(report), as: UTF8.self)
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SAYSO_DEVICE_SPEECH_PROBE " + text)
    }

    private final class Deadline { var exceeded = false }

    /// After 45 seconds, request cancellation and close the owned analyzer/service.
    /// Completion remains cooperative; this is not a hard wall-clock deadline.
    /// Parent test cancellation requests the same cleanup without waiting for the timer.
    private func bounded(operation: @escaping @MainActor () async throws -> String,
                         cancel: @escaping @MainActor () async -> Void) async throws -> String {
        let deadline = Deadline()
        let worker = Task {
            try Task.checkCancellation()
            return try await operation()
        }
        let timer = Task {
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            deadline.exceeded = true
            worker.cancel()
            await cancel()
        }
        defer { timer.cancel() }
        do {
            let value = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let value = try await worker.value
                try Task.checkCancellation()
                return value
            } onCancel: {
                worker.cancel()
                timer.cancel()
                Task { @MainActor in await cancel() }
            }
            if deadline.exceeded { throw ProbeFailure.deadline }
            return value
        } catch {
            await cancel()
            if deadline.exceeded { throw ProbeFailure.deadline }
            throw error
        }
    }

    private struct ProbeReport: Encodable {
        let operatingSystem: String
        let fixtureSHA256: String
        let syntheticUtterance: String
        let fixtureFrames: AVAudioFramePosition
        let fixtureDurationSeconds: Double
        let locale = "en-US"
        let microphoneOpened = false
        let cancellationTriggerSecondsPerPath = 45
        let cancellationCompletion = "Cooperative: cancellation closes owned speech resources and awaits the worker; 45 seconds is not a hard completion deadline."
        let interpretation = "Synthetic file recognition only. This does not exercise microphone capture, audio routes, background recording, or writing models. Missing direct-path result counts are not zeros; production diagnostics are retained verbatim."
        var paths: [PathReport] = []
    }

    private struct PathReport: Encodable {
        let path: String
        var completed = false
        var nonempty = false
        var elapsedSeconds: Double?
        var transcript: String?
        var error: ErrorReport?
        var inputFrameCount: Int64?
        var convertedBufferCount: Int?
        var convertedDurationSeconds: Double?
        var lastConsumedAudioSeconds: Double?
        var resultCount: Int?
        var nonemptyResultCount: Int?
        var finalResultCount: Int?
        var maximumAccumulatedCharacters: Int?
    }

    private struct ErrorReport: Encodable {
        let domain: String
        let code: Int
        let description: String
        init(_ error: Error) {
            let error = error as NSError
            domain = error.domain; code = error.code; description = error.localizedDescription
        }
    }

    private enum ProbeFailure: LocalizedError {
        case deadline, unavailable, missingFormat, noSamples, overrun
        var errorDescription: String? {
            switch self {
            case .deadline: "The 45-second cancellation trigger fired; the synthetic speech operation was cancelled cooperatively."
            case .unavailable: "English on-device SpeechTranscriber is unavailable on this physical device."
            case .missingFormat: "No compatible on-device analyzer format was available."
            case .noSamples: "SpeechAnalyzer consumed no synthetic audio samples."
            case .overrun: "Synthetic analyzer input stream dropped a buffer."
            }
        }
    }

    @MainActor
    private final class StreamedProbe {
        var report = PathReport(path: "production-converter-100ms-stream")
        private var analyzer: SpeechAnalyzer?
        private var ownedLocale: Locale?
        private var downloadProgress: Progress?
        private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
        private var conversionTask: Task<ConversionCounts, Error>?
        private var analysisTask: Task<CMTime?, Error>?
        private var resultsTask: Task<Void, Error>?
        private var transcript = SpeechTranscriptAccumulator()

        func recognize(_ url: URL) async throws -> String {
            guard SpeechTranscriber.isAvailable,
                  let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
                throw ProbeFailure.unavailable
            }
            try Task.checkCancellation()
            let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            self.analyzer = analyzer
            let reserved = try await AssetInventory.reserve(locale: locale)
            if Task.isCancelled {
                if reserved { await AssetInventory.release(reservedLocale: locale) }
                throw CancellationError()
            }
            if reserved { ownedLocale = locale }
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try Task.checkCancellation()
                downloadProgress = installation.progress
                try await installation.downloadAndInstall()
                downloadProgress = nil
            }
            try Task.checkCancellation()
            let sourceFile = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: sourceFile.processingFormat) else {
                throw ProbeFailure.missingFormat
            }
            try Task.checkCancellation()
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation()
            let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(256))
            self.continuation = continuation
            report.resultCount = 0; report.nonemptyResultCount = 0; report.finalResultCount = 0; report.maximumAccumulatedCharacters = 0
            let results = Task { [self] in
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    report.resultCount = (report.resultCount ?? 0) + 1
                    if !result.text.characters.isEmpty { report.nonemptyResultCount = (report.nonemptyResultCount ?? 0) + 1 }
                    if result.isFinal { report.finalResultCount = (report.finalResultCount ?? 0) + 1 }
                    transcript.replace(text: result.text, in: result.range)
                    report.maximumAccumulatedCharacters = max(report.maximumAccumulatedCharacters ?? 0, transcript.text.count)
                }
            }
            resultsTask = results
            let analysis = Task { try await analyzer.analyzeSequence(stream) }
            analysisTask = analysis
            let conversion = Task.detached(priority: .userInitiated) {
                do {
                    let counts = try Self.convertFile(url, destination: format, continuation: continuation)
                    continuation.finish()
                    return counts
                } catch {
                    continuation.finish(throwing: error)
                    throw error
                }
            }
            conversionTask = conversion
            let counts = try await conversion.value
            report.inputFrameCount = counts.frames
            report.convertedBufferCount = counts.buffers
            report.convertedDurationSeconds = counts.seconds
            guard let last = try await analysis.value else { throw ProbeFailure.noSamples }
            report.lastConsumedAudioSeconds = last.seconds.isFinite ? last.seconds : nil
            try Task.checkCancellation()
            try await analyzer.finalizeAndFinish(through: last)
            try await results.value
            try Task.checkCancellation()
            return transcript.text
        }

        func cancel() async {
            downloadProgress?.cancel(); downloadProgress = nil
            continuation?.finish(); continuation = nil
            conversionTask?.cancel(); analysisTask?.cancel(); resultsTask?.cancel()
            let finishing = analyzer; analyzer = nil
            await finishing?.cancelAndFinishNow()
            if let locale = ownedLocale {
                ownedLocale = nil
                await AssetInventory.release(reservedLocale: locale)
            }
        }

        private struct ConversionCounts: Sendable { var frames: Int64 = 0; var buffers = 0; var seconds = 0.0 }

        nonisolated private static func convertFile(_ url: URL, destination: AVAudioFormat,
            continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) throws -> ConversionCounts {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let converter = try SpeechAudioConverter(source: file.processingFormat, destination: destination)
            let chunkFrames = AVAudioFrameCount((file.processingFormat.sampleRate * 0.1).rounded(.up))
            var counts = ConversionCounts()
            func yield(_ inputs: [AnalyzerInput]) throws {
                for input in inputs {
                    switch continuation.yield(input) {
                    case .enqueued: break
                    case .dropped: throw ProbeFailure.overrun
                    case .terminated: throw CancellationError()
                    @unknown default: throw ProbeFailure.overrun
                    }
                    counts.buffers += 1
                    counts.seconds += input.bufferDuration.seconds
                }
            }
            while file.framePosition < file.length {
                try Task.checkCancellation()
                // Fresh storage for every chunk: the native converter may retain it.
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames))
                try file.read(into: buffer, frameCount: chunkFrames)
                guard buffer.frameLength > 0 else { break }
                counts.frames += Int64(buffer.frameLength)
                let captured = AVReadOnlyAudioPCMBuffer(copying: buffer)
                try yield(converter.convert(AVAudioPCMBuffer(copying: captured)))
            }
            try yield(converter.flush())
            return counts
        }
    }
}
