import AVFoundation
import CoreMedia
import Foundation
import Observation
import Speech
import UIKit

@MainActor
protocol SpeechTranscribing: AnyObject {
    var partialText: String { get }
    var level: Double { get }
    var status: String { get }
    var isRecording: Bool { get }
    var diagnosticsReport: String? { get }
    var usesAutomaticLanguageDetection: Bool { get }
    var onInterruption: (() -> Void)? { get set }
    func resetTranscript()
    func start(localeIdentifier: String, contextualStrings: [String]) async throws
    func stop() async throws -> String
    func cancel() async
    func transcribeFile(at url: URL, localeIdentifier: String, contextualStrings: [String]) async throws -> String
}

extension SpeechTranscribing {
    var diagnosticsReport: String? { nil }
    var usesAutomaticLanguageDetection: Bool { false }
}

/// Owns one on-device transcription at a time. Speech assets may be downloaded
/// from Apple; recorded and imported audio is processed on the device.
@MainActor
@Observable
final class SpeechService: SpeechTranscribing {
    private(set) var partialText = ""
    private(set) var level = 0.0
    private(set) var status = "Ready"
    private(set) var isRecording = false
    /// Only technical counters from the last attempt, held in memory. Never audio or words.
    private(set) var diagnosticsReport: String?

    /// Capture has stopped. The caller can use `stop()` to finalize what was heard.
    var onInterruption: (() -> Void)?

    @ObservationIgnored private var session: SpeechSession?

    func resetTranscript() {
        guard session == nil else { return }
        partialText = ""
        level = 0
    }

    func start(localeIdentifier: String, contextualStrings: [String] = []) async throws {
        let session = try beginSession(kind: .microphone)
        session.diagnostics.localeIdentifier = localeIdentifier
        do {
            try ensureDeviceSupport()
            status = "Allow microphone access"
            guard await AVAudioApplication.requestRecordPermission() else {
                throw SpeechServiceError.microphonePermissionDenied
            }
            try checkActive(session)
            let analyzer = try await prepare(session, localeIdentifier: localeIdentifier,
                                             contextualStrings: contextualStrings)
            try checkActive(session)

            try requireForegroundForCapture()
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try audioSession.setActive(true)
            session.hasAudioSession = true

            let engine = AVAudioEngine()
            session.engine = engine
            let input = engine.inputNode
            let captureFormat = input.outputFormat(forBus: 0)
            session.diagnostics.inputPortTypes = audioSession.currentRoute.inputs.map { $0.portType.rawValue }
            session.diagnostics.captureFormat = Self.describe(captureFormat)
            guard captureFormat.sampleRate > 0, captureFormat.channelCount > 0 else {
                throw SpeechServiceError.noMicrophone
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: analyzer.modules, considering: captureFormat
            ) else {
                throw SpeechServiceError.incompatibleAudio
            }
            try checkActive(session)
            session.diagnostics.analyzerFormat = Self.describe(format)
            status = "Preparing on-device speech"
            try await analyzer.prepareToAnalyze(in: format)
            try checkActive(session)

            let (captureStream, captureContinuation) = AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>
                .makeStream(bufferingPolicy: .bufferingOldest(128))
            let (analyzerStream, analyzerContinuation) = AsyncThrowingStream<AnalyzerInput, Error>
                .makeStream(bufferingPolicy: .bufferingOldest(256))
            session.captureContinuation = captureContinuation
            session.analyzerContinuation = analyzerContinuation

            let converter = try SpeechAudioConverter(source: captureFormat, destination: format)
            session.conversionTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    for try await chunk in captureStream {
                        try Task.checkCancellation()
                        let buffer = AVAudioPCMBuffer(copying: chunk)
                        let amplitude = SpeechAudioConverter.normalizedLevel(buffer)
                        // Capture and generated output are separate stages. A
                        // converter or enqueue failure must not erase evidence
                        // that the microphone delivered this buffer.
                        await self?.observeCapture(frames: Int(buffer.frameLength), level: amplitude,
                                                   for: session.id)
                        let converted = try converter.convert(buffer)
                        await self?.observeConverted(converted.map { CMTimeGetSeconds($0.bufferDuration) },
                                                     for: session.id)
                        for input in converted {
                            try Self.yield(input, to: analyzerContinuation)
                        }
                    }
                    let tail = try converter.flush()
                    await self?.observeConverted(tail.map { CMTimeGetSeconds($0.bufferDuration) }, for: session.id)
                    for buffer in tail {
                        try Self.yield(buffer, to: analyzerContinuation)
                    }
                    analyzerContinuation.finish()
                } catch {
                    analyzerContinuation.finish(throwing: error)
                    await self?.processingFailed(error, sessionID: session.id)
                    throw error
                }
            }
            session.analysisTask = Task { [weak self] in
                do {
                    return try await analyzer.analyzeSequence(analyzerStream)
                } catch {
                    self?.processingFailed(error, sessionID: session.id)
                    throw error
                }
            }

            // Native read-only buffers are Sendable values that can outlive the
            // callback. Mutable copying, conversion and metering stay on the
            // single consumer task, with observable changes on the main actor.
            // Audio taps support requests of 100–400 ms.
            let tapFrameCount = AVAudioFrameCount((captureFormat.sampleRate * 0.1).rounded(.up))
            try input.installAudioTap(onBus: 0, bufferSize: tapFrameCount, format: captureFormat) { buffer, _ in
                guard buffer.frameLength > 0 else { return }
                if case .dropped = captureContinuation.yield(buffer) {
                    captureContinuation.finish(throwing: SpeechServiceError.audioOverrun)
                }
            }
            session.hasTap = true
            installInterruptionObservers(for: session)
            engine.prepare()
            try requireForegroundForCapture()
            try engine.start()
            session.isCapturing = true
            isRecording = true
            status = "Listening on device"
        } catch {
            await finishFailedSession(session, error: error)
            throw error
        }
    }

    /// Drains captured audio before finalizing, so the end of a sentence is retained.
    func stop() async throws -> String {
        guard let session, session.kind == .microphone, !session.isStopping,
              session.analyzer != nil, !session.isCancelled else {
            throw SpeechServiceError.notRecording
        }
        session.isStopping = true
        if session.diagnostics.stopReason == "unknown" { session.diagnostics.stopReason = "stop requested" }
        status = "Finishing transcription"
        stopCapture(session)
        do {
            try await session.conversionTask?.value
            let lastSample = try await session.analysisTask?.value
            session.diagnostics.analyzerLastSampleSeconds = lastSample.map(CMTimeGetSeconds)
            try checkActive(session)
            if let lastSample {
                try await session.analyzer?.finalizeAndFinish(through: lastSample)
            } else {
                await session.analyzer?.cancelAndFinishNow()
                if session.diagnostics.captureFrames == 0 { throw SpeechServiceError.noAudioCaptured }
                if session.diagnostics.convertedBuffers == 0 { throw SpeechServiceError.audioNotConverted }
                throw SpeechServiceError.audioNotAnalyzed
            }
            try await session.resultsTask?.value
            try checkActive(session)
            if let failure = session.failure { throw failure }
            let transcript = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                throw SpeechServiceError.noWordsRecognized(session.diagnostics.localeIdentifier)
            }
            finishDiagnostics(session, outcome: "transcribed")
            await cleanUp(session)
            status = "Ready"
            return transcript
        } catch {
            await finishFailedSession(session, error: error)
            throw error
        }
    }

    func cancel() async {
        guard let session else { return }
        session.isCancelled = true
        session.diagnostics.stopReason = "cancel requested"
        finishDiagnostics(session, outcome: "cancelled")
        await cleanUp(session)
        status = "Ready"
        level = 0
    }

    /// Imports the original file directly into SpeechAnalyzer. Its file API
    /// performs format conversion and streams the file without loading it all.
    func transcribeFile(at url: URL, localeIdentifier: String,
                        contextualStrings: [String] = []) async throws -> String {
        let session = try beginSession(kind: .file)
        session.diagnostics.localeIdentifier = localeIdentifier
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        do {
            try ensureDeviceSupport()
            let file = try AVAudioFile(forReading: url)
            session.diagnostics.captureFormat = Self.describe(file.processingFormat)
            session.diagnostics.stopReason = "end of file"
            guard file.length > 0 else { throw SpeechServiceError.emptyFile }
            let analyzer = try await prepare(session, localeIdentifier: localeIdentifier,
                                             contextualStrings: contextualStrings)
            try checkActive(session)
            status = "Transcribing on device"
            session.analysisTask = Task {
                try await analyzer.analyzeSequence(from: file)
            }
            let lastSample = try await session.analysisTask?.value
            session.diagnostics.analyzerLastSampleSeconds = lastSample.map(CMTimeGetSeconds)
            try checkActive(session)
            if let lastSample {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            try await session.resultsTask?.value
            try checkActive(session)
            let transcript = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            finishDiagnostics(session, outcome: transcript.isEmpty ? "no words from file" : "transcribed")
            await cleanUp(session)
            status = "Ready"
            return transcript
        } catch {
            await finishFailedSession(session, error: error)
            throw error
        }
    }

    private func beginSession(kind: SpeechSession.Kind) throws -> SpeechSession {
        guard session == nil else { throw SpeechServiceError.busy }
        let newSession = SpeechSession(kind: kind)
        newSession.diagnostics = SpeechDiagnostics(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        session = newSession
        diagnosticsReport = nil
        partialText = ""
        level = 0
        return newSession
    }

    private func requireForegroundForCapture() throws {
        guard UIApplication.shared.applicationState == .active else { throw SpeechServiceError.foregroundRequired }
    }

    private func ensureDeviceSupport() throws {
        guard SpeechTranscriber.isAvailable else { throw SpeechServiceError.unavailable }
    }

    private func checkActive(_ candidate: SpeechSession) throws {
        try Task.checkCancellation()
        guard session === candidate, !candidate.isCancelled else { throw CancellationError() }
        if let failure = candidate.failure { throw failure }
    }

    private func prepare(_ session: SpeechSession, localeIdentifier: String,
                         contextualStrings: [String]) async throws -> SpeechAnalyzer {
        status = "Checking speech language"
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: localeIdentifier)
        ) else {
            throw SpeechServiceError.unsupportedLanguage(localeIdentifier)
        }
        try checkActive(session)
        session.diagnostics.localeIdentifier = locale.identifier
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        session.transcriber = transcriber
        // Never release another component's existing reservation. `reserve`
        // returns true only when this call actually adds the reservation.
        let ownsReservation = try await AssetInventory.reserve(locale: locale)
        if ownsReservation {
            // Cancellation can finish while the reservation request is in flight.
            // A late reservation still belongs to us and must be released here.
            if self.session !== session || session.isCancelled {
                await AssetInventory.release(reservedLocale: locale)
                throw CancellationError()
            }
            session.reservedLocale = locale
        }
        try checkActive(session)

        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        try checkActive(session)
        guard assetStatus != .unsupported else {
            throw SpeechServiceError.unsupportedLanguage(localeIdentifier)
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try checkActive(session)
            session.downloadProgress = request.progress
            status = "Downloading speech language · 0%"
            session.downloadMonitor = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.session === session, !session.isCancelled else { return }
                    let percent = Int((request.progress.fractionCompleted * 100).clamped(to: 0...100))
                    self.status = "Downloading speech language · \(percent)%"
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
            }
            try await request.downloadAndInstall()
            session.downloadMonitor?.cancel()
            session.downloadMonitor = nil
            session.downloadProgress = nil
            try checkActive(session)
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        session.analyzer = analyzer
        let phrases = Array(Set(contextualStrings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        if !phrases.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = phrases
            try await analyzer.setContext(context)
            try checkActive(session)
        }
        session.resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard let self, self.session === session, !session.isCancelled else { return }
                    session.transcript.replace(text: result.text, in: result.range)
                    self.partialText = session.transcript.text
                    session.diagnostics.observeResult(characters: result.text.characters.count,
                                                      accumulatedCharacters: self.partialText.count)
                }
            } catch {
                self?.processingFailed(error, sessionID: session.id)
                throw error
            }
        }
        return analyzer
    }

    private func updateLevel(_ amplitude: Double, for sessionID: UUID) {
        guard session?.id == sessionID, isRecording else { return }
        // A quick attack and gentle release avoids a flickering waveform.
        let weight = amplitude > level ? 0.65 : 0.25
        level = (level * (1 - weight) + amplitude * weight).clamped(to: 0...1)
    }

    private func observeCapture(frames: Int, level: Double, for sessionID: UUID) {
        guard let session, session.id == sessionID else { return }
        session.diagnostics.observeCapture(frames: frames, level: level)
        updateLevel(level, for: sessionID)
    }

    private func observeConverted(_ durations: [Double], for sessionID: UUID) {
        guard let session, session.id == sessionID else { return }
        for duration in durations { session.diagnostics.observeConverted(duration: duration) }
    }

    private func finishDiagnostics(_ session: SpeechSession, outcome: String) {
        guard self.session === session else { return }
        session.diagnostics.finish(characters: partialText.count, outcome: outcome,
                                   stopReason: session.diagnostics.stopReason)
        diagnosticsReport = session.diagnostics.renderReport()
        #if DEBUG
        print(diagnosticsReport ?? "")
        #endif
    }

    nonisolated private static func describe(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate) Hz, \(format.channelCount) channels, PCM \(format.commonFormat.rawValue), interleaved \(format.isInterleaved)"
    }

    private func processingFailed(_ error: Error, sessionID: UUID) {
        guard let session, session.id == sessionID, !session.isCancelled else { return }
        if session.failure == nil { session.failure = error }
        session.diagnostics.stopReason = "processing error"
        guard session.kind == .microphone, !session.isStopping else { return }
        interrupt(session)
    }

    private func installInterruptionObservers(for session: SpeechSession) {
        let center = NotificationCenter.default
        // Any loss of the active audio session ends this recording. Resumption
        // recommendations do not restart capture without another user action.
        session.observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            guard let target = self else { return }
            Task { @MainActor in target.interrupt(session, reason: "audio session inactive") }
        })
        session.observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                     object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            guard let target = self else { return }
            Task { @MainActor in target.interrupt(session, reason: "input device disconnected") }
        })
        session.observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            guard let target = self else { return }
            Task { @MainActor in target.interrupt(session, reason: "audio services reset") }
        })
        session.observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                     object: session.engine, queue: .main) { [weak self] _ in
            guard let target = self else { return }
            Task { @MainActor in
                guard session.isCapturing, session.engine?.isRunning == false else { return }
                target.interrupt(session, reason: "audio engine stopped after configuration change")
            }
        })
    }

    private func interrupt(_ session: SpeechSession, reason: String? = nil) {
        guard self.session === session, !session.isCancelled, !session.isStopping,
              !session.didInterrupt else { return }
        session.didInterrupt = true
        if let reason { session.diagnostics.stopReason = reason }
        stopCapture(session)
        status = "Recording interrupted"
        onInterruption?()
    }

    private func stopCapture(_ session: SpeechSession) {
        session.isCapturing = false
        session.engine?.stop()
        if session.hasTap {
            session.engine?.inputNode.removeTap(onBus: 0)
            session.hasTap = false
        }
        session.captureContinuation?.finish()
        session.captureContinuation = nil
        isRecording = false
        level = 0
    }

    private func finishFailedSession(_ session: SpeechSession, error: Error) async {
        // An old, cancelled prepare operation must not overwrite a newer session.
        let wasCurrent = self.session === session
        let wasCancelled = session.isCancelled || error is CancellationError
        let code = error as NSError
        finishDiagnostics(session, outcome: wasCancelled ? "cancelled" : "error \(code.domain) (\(code.code))")
        await cleanUp(session)
        if wasCurrent, self.session == nil {
            status = wasCancelled ? "Ready" : "Couldn’t transcribe"
        }
    }

    private func cleanUp(_ session: SpeechSession) async {
        if let cleanup = session.cleanupTask { await cleanup.value; return }
        let cleanup = Task { @MainActor [weak self] in
            session.downloadMonitor?.cancel()
            session.downloadMonitor = nil
            session.downloadProgress?.cancel()
            session.downloadProgress = nil
            self?.stopCapture(session)
            for observer in session.observers { NotificationCenter.default.removeObserver(observer) }
            session.observers.removeAll()
            session.conversionTask?.cancel()
            session.analysisTask?.cancel()
            session.resultsTask?.cancel()
            session.analyzerContinuation?.finish()
            session.analyzerContinuation = nil
            if session.hasAudioSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                session.hasAudioSession = false
            }
            await session.analyzer?.cancelAndFinishNow()
            if let locale = session.reservedLocale {
                await AssetInventory.release(reservedLocale: locale)
                session.reservedLocale = nil
            }
            session.engine = nil
            session.analyzer = nil
            session.transcriber = nil
            if self?.session === session { self?.session = nil }
        }
        session.cleanupTask = cleanup
        await cleanup.value
    }

    nonisolated private static func yield(_ input: AnalyzerInput,
                                         to continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) throws {
        switch continuation.yield(input) {
        case .enqueued: break
        case .dropped: throw SpeechServiceError.audioOverrun
        case .terminated: throw CancellationError()
        @unknown default: throw SpeechServiceError.audioOverrun
        }
    }
}

@MainActor
private final class SpeechSession {
    enum Kind { case microphone, file }
    let id = UUID()
    let kind: Kind
    var engine: AVAudioEngine?
    var analyzer: SpeechAnalyzer?
    var transcriber: SpeechTranscriber?
    var captureContinuation: AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>.Continuation?
    var analyzerContinuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    var conversionTask: Task<Void, Error>?
    var analysisTask: Task<CMTime?, Error>?
    var resultsTask: Task<Void, Error>?
    var downloadMonitor: Task<Void, Never>?
    var downloadProgress: Progress?
    var cleanupTask: Task<Void, Never>?
    var reservedLocale: Locale?
    var observers: [NSObjectProtocol] = []
    var transcript = SpeechTranscriptAccumulator()
    var diagnostics = SpeechDiagnostics()
    var failure: Error?
    var hasAudioSession = false
    var hasTap = false
    var isCapturing = false
    var isStopping = false
    var isCancelled = false
    var didInterrupt = false

    init(kind: Kind) { self.kind = kind }
}

/// Uses Speech's word-level timestamps to replace volatile interpretations in
/// place. Final phrases accumulate without duplicating their earlier drafts.
nonisolated struct SpeechTranscriptAccumulator {
    private typealias AudioTimeAttribute = AttributeScopes.SpeechAttributes.TimeRangeAttribute
    private var attributedText = AttributedString()

    var text: String { String(attributedText.characters).trimmingCharacters(in: .whitespacesAndNewlines) }

    mutating func replace(text: AttributedString, in audioRange: CMTimeRange) {
        var replacement = text
        // Time-indexed results normally include word ranges. A phrase-level
        // range keeps replacement correct if a provider omits the attributes.
        if !replacement.characters.isEmpty,
           !replacement.runs.contains(where: { $0[AudioTimeAttribute.self] != nil }) {
            replacement[AudioTimeAttribute.self] = audioRange
        }
        if let range = attributedText.rangeOfAudioTimeRangeAttributes(intersecting: audioRange) {
            attributedText.replaceSubrange(range, with: replacement)
        } else if let laterRun = attributedText.runs.first(where: {
            guard let range = $0[AudioTimeAttribute.self] else { return false }
            return CMTimeCompare(range.start, audioRange.start) > 0
        }) {
            attributedText.insert(replacement, at: laterRun.range.lowerBound)
        } else {
            attributedText.append(replacement)
        }
    }
}

nonisolated enum SpeechServiceError: LocalizedError {
    case unavailable
    case microphonePermissionDenied
    case foregroundRequired
    case unsupportedLanguage(String)
    case noMicrophone
    case noAudioCaptured
    case audioNotConverted
    case audioNotAnalyzed
    case noWordsRecognized(String)
    case incompatibleAudio
    case audioOverrun
    case emptyFile
    case busy
    case notRecording

    var errorDescription: String? {
        switch self {
        case .unavailable:
            #if targetEnvironment(simulator)
            "Apple’s on-device speech model isn’t available in this simulator. Try recording on your iPhone."
            #else
            "Apple’s on-device speech model isn’t available on this device."
            #endif
        case .foregroundRequired:
            "Open Sayso to begin recording, then return to the app you’re writing in."
        case .microphonePermissionDenied:
            "Allow microphone access for Sayso in Settings to start recording."
        case .unsupportedLanguage(let identifier):
            "Apple’s on-device speech model doesn’t support \(Locale.current.localizedString(forIdentifier: identifier) ?? identifier). Choose another language."
        case .noMicrophone:
            "No microphone is available. Check your audio connection and try again."
        case .noAudioCaptured:
            "Sayso didn’t receive audio from the microphone. Try recording again for a few seconds."
        case .audioNotConverted:
            "Microphone audio was received, but it couldn’t be converted for recognition. Please copy the diagnostics for this attempt."
        case .audioNotAnalyzed:
            "Microphone audio was received, but the speech recognizer didn’t process it. Please copy the diagnostics for this attempt."
        case .noWordsRecognized(let identifier):
            "Audio was received, but no words were transcribed. Check that Sayso’s language matches your speech (\(Locale.current.localizedString(forIdentifier: identifier) ?? identifier)). You can copy diagnostics for this attempt."
        case .incompatibleAudio:
            "This audio format couldn’t be prepared for on-device transcription."
        case .audioOverrun:
            "Transcription couldn’t keep up with the microphone. Please try recording again."
        case .emptyFile:
            "This file doesn’t contain any audio."
        case .busy:
            "Finish the current transcription before starting another."
        case .notRecording:
            "There isn’t an active recording to finish."
        }
    }
}

nonisolated private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
