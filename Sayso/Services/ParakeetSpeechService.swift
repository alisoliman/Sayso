import AVFoundation
import Foundation
import Observation
import UIKit

/// A local runtime receives complete recordings as mono Float32 PCM at 16 kHz.
/// Implementations must not download assets as part of preparing or recognizing.
nonisolated protocol ParakeetRecognizing: Sendable {
    func prepare() async throws
    func releasePreparedResources() async
    func transcribe(_ samples: [Float]) async throws -> String
}

extension ParakeetRecognizing {
    func releasePreparedResources() async {}
}

/// First-version Parakeet recognition is deliberately batch based. Microphone
/// audio stays in memory and is sent to the local runtime only after capture ends.
@MainActor @Observable
final class ParakeetSpeechService: SpeechTranscribing {
    private(set) var partialText = ""
    private(set) var level = 0.0
    private(set) var status = "Ready"
    private(set) var isRecording = false
    private(set) var diagnosticsReport: String?
    var onInterruption: (() -> Void)?
    var usesAutomaticLanguageDetection: Bool { true }

    @ObservationIgnored private let runtime: any ParakeetRecognizing
    @ObservationIgnored private let requestMicrophonePermission: () async -> Bool
    @ObservationIgnored private var session: ParakeetSession?
    @ObservationIgnored private var warmup: (id: UUID, task: Task<Void, Error>)?
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private var warmupGeneration = UUID()

    init(runtime: any ParakeetRecognizing,
         requestMicrophonePermission: @escaping () async -> Bool = { await AVAudioApplication.requestRecordPermission() }) {
        self.runtime = runtime
        self.requestMicrophonePermission = requestMicrophonePermission
    }

    func resetTranscript() {
        guard session == nil else { return }
        partialText = ""
        level = 0
    }

    func prewarm(localeIdentifier: String, contextualStrings: [String] = []) async throws {
        try Task.checkCancellation()
        if isPrepared { return }
        if let warmup {
            try await warmup.task.value
            guard warmupGeneration == warmup.id else { throw CancellationError() }
            try Task.checkCancellation()
            return
        }
        let id = UUID()
        warmupGeneration = id
        let runtime = runtime
        let task = Task { try await runtime.prepare() }
        warmup = (id, task)
        do {
            try await task.value
            guard warmupGeneration == id else { throw CancellationError() }
            if warmup?.id == id { isPrepared = true; warmup = nil }
            try Task.checkCancellation()
        } catch {
            if warmup?.id == id { warmup = nil }
            throw error
        }
    }

    func releasePreparedResources() async {
        guard session == nil else { return }
        let pending = warmup
        warmupGeneration = UUID()
        warmup = nil
        isPrepared = false
        pending?.task.cancel()
        await runtime.releasePreparedResources()
    }

    func start(localeIdentifier: String, contextualStrings: [String] = []) async throws {
        let session = try beginSession()
        do {
            // Batch recognition only needs the model after Stop. Start its
            // preparation now while the microphone begins capturing the user.
            beginPreparation(session)
            status = "Allow microphone access"
            guard await requestMicrophonePermission() else {
                throw SpeechServiceError.microphonePermissionDenied
            }
            try checkActive(session)
            try requireForeground()

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try audioSession.setActive(true)
            session.hasAudioSession = true
            let engine = AVAudioEngine()
            session.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechServiceError.noMicrophone }
            session.diagnostics.captureFormat = "\(format.sampleRate) Hz, \(format.channelCount) channels"
            session.diagnostics.inputPortTypes = audioSession.currentRoute.inputs.map { $0.portType.rawValue }
            let converter = try ParakeetAudioConverter(source: format)
            let (stream, continuation) = AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>
                .makeStream(bufferingPolicy: .bufferingOldest(128))
            session.captureContinuation = continuation
            let sessionID = session.id
            session.conversionTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    var samples = ParakeetAudioSamples()
                    var inputFrames = 0
                    let maximumFrames = Int(format.sampleRate * ParakeetAudioSamples.maximumDuration)
                    for try await chunk in stream {
                        try Task.checkCancellation()
                        let buffer = AVAudioPCMBuffer(copying: chunk)
                        let remaining = maximumFrames - inputFrames
                        // Stop exactly at the limit; a final tap can cross it.
                        if Int(buffer.frameLength) > remaining { buffer.frameLength = AVAudioFrameCount(remaining) }
                        inputFrames += Int(buffer.frameLength)
                        let amplitude = ParakeetAudioConverter.normalizedLevel(buffer)
                        await self?.observeCapture(frames: Int(buffer.frameLength), amplitude: amplitude, for: sessionID)
                        let converted = try converter.convert(buffer)
                        try samples.append(converted)
                        await self?.observeConverted(count: converted.count, for: sessionID)
                        if inputFrames == maximumFrames {
                            await self?.reachedRecordingLimit(sessionID)
                            break
                        }
                    }
                    try Task.checkCancellation()
                    let tail = try converter.flush()
                    try samples.append(tail)
                    await self?.observeConverted(count: tail.count, for: sessionID)
                    return samples.values
                } catch {
                    await self?.processingFailed(error, sessionID: sessionID)
                    throw error
                }
            }

            // Read-only tap buffers own Sendable audio. Copying, metering,
            // resampling and accumulation all belong to the serial consumer.
            let frames = AVAudioFrameCount((format.sampleRate * 0.1).rounded(.up))
            try input.installAudioTap(onBus: 0, bufferSize: frames, format: format) { buffer, _ in
                guard buffer.frameLength > 0 else { return }
                if case .dropped = continuation.yield(buffer) {
                    continuation.finish(throwing: SpeechServiceError.audioOverrun)
                }
            }
            session.hasTap = true
            installInterruptionObservers(for: session)
            engine.prepare()
            try requireForeground()
            try engine.start()
            session.isCapturing = true
            isRecording = true
            status = "Recording · text appears after Stop"
        } catch {
            finishFailedSession(session, error: error)
            throw error
        }
    }

    func stop() async throws -> String {
        guard let session, session.conversionTask != nil,
              !session.isStopping, !session.isCancelled else { throw SpeechServiceError.notRecording }
        session.isStopping = true
        if session.diagnostics.stopReason == "unknown" { session.diagnostics.stopReason = "stop requested" }
        stopCapture(session)
        status = "Preparing recorded audio"
        do {
            let samples = try await session.conversionTask!.value
            try checkActive(session)
            try await prepare(session)
            return try await recognize(samples, session: session)
        } catch {
            finishFailedSession(session, error: error)
            throw error
        }
    }

    func cancel() async {
        guard let session else { return }
        session.isCancelled = true
        session.diagnostics.stopReason = "cancel requested"
        finishDiagnostics(session, outcome: "cancelled")
        cleanUp(session)
        status = "Ready"
    }

    private func beginSession() throws -> ParakeetSession {
        guard session == nil else { throw SpeechServiceError.busy }
        let next = ParakeetSession()
        next.diagnostics = SpeechDiagnostics(
            localeIdentifier: "und",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        next.diagnostics.analyzerFormat = "Parakeet · 16000 Hz, mono Float32"
        session = next
        partialText = ""
        level = 0
        diagnosticsReport = nil
        return next
    }

    private func prepare(_ session: ParakeetSession) async throws {
        if !isPrepared { status = "Getting ready…" }
        beginPreparation(session)
        try await session.prepareTask!.value
        try checkActive(session)
    }

    private func beginPreparation(_ session: ParakeetSession) {
        guard session.prepareTask == nil else { return }
        session.prepareTask = Task { [weak self] in
            guard let self else { throw CancellationError() }
            do {
                try await self.prewarm(localeIdentifier: "und")
            } catch {
                // A cold load can finish while capture is underway. Stop a
                // failed recording immediately rather than waiting for Stop.
                // Intentional cancellation and retired sessions remain silent.
                if !Task.isCancelled, !(error is CancellationError) {
                    self.processingFailed(error, sessionID: session.id)
                }
                throw error
            }
        }
    }

    private func recognize(_ samples: [Float], session: ParakeetSession) async throws -> String {
        guard !samples.isEmpty else { throw SpeechServiceError.noAudioCaptured }
        try ParakeetAudioSamples.validate(count: samples.count)
        guard samples.count >= ParakeetAudioSamples.minimumCount else { throw ParakeetSpeechError.audioTooShort }
        try checkActive(session)
        status = "Transcribing with local Parakeet"
        let runtime = runtime
        session.recognitionTask = Task { try await runtime.transcribe(samples) }
        let text = try await session.recognitionTask!.value.trimmingCharacters(in: .whitespacesAndNewlines)
        try checkActive(session)
        guard !text.isEmpty else { throw ParakeetSpeechError.noWordsRecognized }
        partialText = text
        session.diagnostics.observeResult(characters: text.count, accumulatedCharacters: text.count)
        finishDiagnostics(session, outcome: "transcribed")
        cleanUp(session)
        status = "Ready"
        return text
    }

    private func checkActive(_ candidate: ParakeetSession) throws {
        try Task.checkCancellation()
        guard session === candidate, !candidate.isCancelled else { throw CancellationError() }
        if let failure = candidate.failure { throw failure }
    }

    private func requireForeground() throws {
        guard UIApplication.shared.applicationState == .active else { throw SpeechServiceError.foregroundRequired }
    }

    private func observeCapture(frames: Int, amplitude: Double, for id: UUID) {
        guard let session, session.id == id else { return }
        session.diagnostics.observeCapture(frames: frames, level: amplitude)
        guard isRecording else { return }
        let weight = amplitude > level ? 0.65 : 0.25
        level = min(1, max(0, level * (1 - weight) + amplitude * weight))
    }

    private func observeConverted(count: Int, for id: UUID) {
        guard let session, session.id == id else { return }
        session.diagnostics.observeConverted(duration: Double(count) / ParakeetAudioSamples.sampleRate)
    }

    private func reachedRecordingLimit(_ id: UUID) {
        guard let session, session.id == id else { return }
        interrupt(session, reason: "10 minute recording limit", status: "10 minute limit reached · finishing recording")
    }

    private func processingFailed(_ error: Error, sessionID: UUID) {
        guard let session, session.id == sessionID, !session.isCancelled else { return }
        if session.failure == nil { session.failure = error }
        interrupt(session, reason: "audio processing error")
    }

    private func installInterruptionObservers(for session: ParakeetSession) {
        let center = NotificationCenter.default
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

    private func interrupt(_ candidate: ParakeetSession, reason: String,
                           status: String = "Recording interrupted") {
        guard session === candidate, !candidate.isCancelled,
              !candidate.isStopping, !candidate.didInterrupt else { return }
        candidate.didInterrupt = true
        candidate.diagnostics.stopReason = reason
        stopCapture(candidate)
        self.status = status
        onInterruption?()
    }

    private func stopCapture(_ candidate: ParakeetSession) {
        candidate.isCapturing = false
        candidate.engine?.stop()
        if candidate.hasTap {
            candidate.engine?.inputNode.removeTap(onBus: 0)
            candidate.hasTap = false
        }
        candidate.captureContinuation?.finish()
        candidate.captureContinuation = nil
        // A late completion may clean up an older session after a new one starts.
        guard session === candidate else { return }
        isRecording = false
        level = 0
    }

    private func finishDiagnostics(_ candidate: ParakeetSession, outcome: String) {
        guard session === candidate else { return }
        candidate.diagnostics.finish(characters: partialText.count, outcome: outcome,
                                     stopReason: candidate.diagnostics.stopReason)
        diagnosticsReport = candidate.diagnostics.renderReport()
    }

    private func finishFailedSession(_ candidate: ParakeetSession, error: Error) {
        let wasCurrent = session === candidate
        let cancelled = candidate.isCancelled || error is CancellationError
        let code = error as NSError
        finishDiagnostics(candidate, outcome: cancelled ? "cancelled" : "error \(code.domain) (\(code.code))")
        cleanUp(candidate)
        if wasCurrent { status = cancelled ? "Ready" : "Couldn’t transcribe" }
    }

    /// Synchronous main-actor cleanup is idempotent and releases capture before a
    /// new session can begin. Late runtime results are rejected by session identity.
    private func cleanUp(_ candidate: ParakeetSession) {
        stopCapture(candidate)
        for observer in candidate.observers { NotificationCenter.default.removeObserver(observer) }
        candidate.observers.removeAll()
        candidate.prepareTask?.cancel()
        candidate.prepareTask = nil
        candidate.conversionTask?.cancel()
        candidate.conversionTask = nil
        candidate.recognitionTask?.cancel()
        candidate.recognitionTask = nil
        if candidate.hasAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            candidate.hasAudioSession = false
        }
        candidate.engine = nil
        if session === candidate { session = nil }
    }
}

@MainActor
private final class ParakeetSession {
    let id = UUID()
    var engine: AVAudioEngine?
    var captureContinuation: AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>.Continuation?
    var prepareTask: Task<Void, Error>?
    var conversionTask: Task<[Float], Error>?
    var recognitionTask: Task<String, Error>?
    var diagnostics = SpeechDiagnostics()
    var observers: [NSObjectProtocol] = []
    var failure: Error?
    var hasAudioSession = false
    var hasTap = false
    var isCapturing = false
    var isStopping = false
    var isCancelled = false
    var didInterrupt = false
}

nonisolated enum ParakeetSpeechError: LocalizedError {
    case audioTooLong
    case audioTooShort
    case noWordsRecognized

    var errorDescription: String? {
        switch self {
        case .audioTooLong: "Local Parakeet supports audio up to 10 minutes. Record for a shorter time."
        case .audioTooShort: "Parakeet needs at least 0.3 seconds of audio. Record a little longer and try again."
        case .noWordsRecognized: "Parakeet didn’t recognize any words in this audio. Try a clearer recording."
        }
    }
}

nonisolated struct ParakeetAudioSamples: Sendable {
    static let sampleRate = 16_000.0
    static let maximumDuration = 600.0
    static let minimumCount = 4_800
    static let maximumCount = 9_600_000
    private(set) var values: [Float] = []

    static func validate(count: Int) throws {
        guard count <= maximumCount else { throw ParakeetSpeechError.audioTooLong }
    }

    mutating func append(_ samples: [Float]) throws {
        // Check before allocating additional memory, including converter tails.
        guard samples.count <= Self.maximumCount - values.count else { throw ParakeetSpeechError.audioTooLong }
        values.append(contentsOf: samples)
    }
}

/// The converter and mutable PCM buffers belong to exactly one serial consumer.
/// This wrapper permits transfer into that task, never concurrent conversion.
nonisolated final class ParakeetAudioConverter: @unchecked Sendable {
    private let source: AVAudioFormat
    private let monoFormat: AVAudioFormat
    private let destination: AVAudioFormat
    private let converter: AVAudioConverter
    private var inputFrames = 0
    private var outputFrames = 0
    private var isFinished = false

    init(source: AVAudioFormat) throws {
        guard source.sampleRate.isFinite, source.sampleRate > 0, source.channelCount > 0,
              [.pcmFormatFloat32, .pcmFormatFloat64, .pcmFormatInt16, .pcmFormatInt32].contains(source.commonFormat),
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                sampleRate: source.sampleRate, channels: 1, interleaved: false),
              let destination = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                sampleRate: ParakeetAudioSamples.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: monoFormat, to: destination) else {
            throw SpeechServiceError.incompatibleAudio
        }
        self.source = source
        self.monoFormat = monoFormat
        self.destination = destination
        self.converter = converter
        converter.primeMethod = .normal
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        try Task.checkCancellation()
        guard !isFinished, buffer.format == source else { throw SpeechServiceError.incompatibleAudio }
        guard buffer.frameLength > 0 else { return [] }
        let mono = try downmix(buffer)
        inputFrames += Int(buffer.frameLength)
        return try drain(input: mono, final: false)
    }

    func flush() throws -> [Float] {
        guard !isFinished else { return [] }
        isFinished = true
        guard inputFrames > 0 else { return [] }
        return try drain(input: nil, final: true)
    }

    private func downmix(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == monoFormat { return buffer }
        guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength),
              let output = mono.floatChannelData?[0] else { throw SpeechServiceError.incompatibleAudio }
        mono.frameLength = buffer.frameLength
        output.update(repeating: 0, count: Int(buffer.frameLength))

        // AVAudioConverter can select only the first input channel even with
        // downmix enabled. Average every channel explicitly before resampling,
        // including interleaved PCM from audio input devices.
        switch source.commonFormat {
        case .pcmFormatFloat32: try mix(buffer, into: output, sample: Float.self) { $0 }
        case .pcmFormatFloat64: try mix(buffer, into: output, sample: Double.self) { Float($0) }
        case .pcmFormatInt16: try mix(buffer, into: output, sample: Int16.self) { Float($0) / 32_768 }
        case .pcmFormatInt32: try mix(buffer, into: output, sample: Int32.self) { Float($0) / 2_147_483_648 }
        default: throw SpeechServiceError.incompatibleAudio
        }
        return mono
    }

    private func mix<Sample>(_ buffer: AVAudioPCMBuffer, into output: UnsafeMutablePointer<Float>,
                             sample: Sample.Type, normalize: (Sample) -> Float) throws {
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let frames = Int(buffer.frameLength)
        let weight = 1 / Float(source.channelCount)
        guard buffers.reduce(0, { $0 + Int($1.mNumberChannels) }) == Int(source.channelCount) else {
            throw SpeechServiceError.incompatibleAudio
        }
        for input in buffers {
            let channels = Int(input.mNumberChannels)
            guard channels > 0, let data = input.mData,
                  Int(input.mDataByteSize) >= frames * channels * MemoryLayout<Sample>.stride else {
                throw SpeechServiceError.incompatibleAudio
            }
            let samples = data.assumingMemoryBound(to: Sample.self)
            for frame in 0..<frames {
                if frame.isMultiple(of: 4_096) { try Task.checkCancellation() }
                for channel in 0..<channels {
                    output[frame] += normalize(samples[frame * channels + channel]) * weight
                }
            }
        }
    }

    private func drain(input: AVAudioPCMBuffer?, final: Bool) throws -> [Float] {
        var cursor = 0
        var values: [Float] = []
        while true {
            try Task.checkCancellation()
            guard let output = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: 4_096) else {
                throw SpeechServiceError.incompatibleAudio
            }
            var inputFailure: Error?
            var conversionFailure: NSError?
            let result = converter.convert(to: output, error: &conversionFailure) { requested, status in
                guard let input, cursor < Int(input.frameLength) else {
                    status.pointee = final ? .endOfStream : .noDataNow
                    return nil
                }
                let count = min(Int(requested), Int(input.frameLength) - cursor)
                guard count > 0,
                      let slice = AVAudioPCMBuffer(pcmFormat: self.monoFormat, frameCapacity: AVAudioFrameCount(count)) else {
                    inputFailure = SpeechServiceError.incompatibleAudio
                    status.pointee = .noDataNow
                    return nil
                }
                slice.frameLength = AVAudioFrameCount(count)
                let sourceBuffers = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
                let targetBuffers = UnsafeMutableAudioBufferListPointer(slice.mutableAudioBufferList)
                let bytesPerFrame = Int(self.monoFormat.streamDescription.pointee.mBytesPerFrame)
                for index in 0..<sourceBuffers.count {
                    guard let from = sourceBuffers[index].mData, let to = targetBuffers[index].mData else {
                        inputFailure = SpeechServiceError.incompatibleAudio
                        status.pointee = .noDataNow
                        return nil
                    }
                    to.copyMemory(from: from.advanced(by: cursor * bytesPerFrame), byteCount: count * bytesPerFrame)
                }
                cursor += count
                status.pointee = .haveData
                return slice
            }
            if let inputFailure { throw inputFailure }
            if let conversionFailure { throw conversionFailure }
            if output.frameLength > 0 {
                guard let channel = output.floatChannelData?[0] else { throw SpeechServiceError.incompatibleAudio }
                // Final filter padding is not part of the recorded audio.
                let expectedFrames = Int((Double(inputFrames) * destination.sampleRate / source.sampleRate).rounded())
                let count = final ? min(Int(output.frameLength), max(0, expectedFrames - outputFrames)) : Int(output.frameLength)
                values.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
                outputFrames += count
            }
            switch result {
            case .haveData: continue
            case .inputRanDry, .endOfStream: return values
            case .error: throw SpeechServiceError.incompatibleAudio
            @unknown default: throw SpeechServiceError.incompatibleAudio
            }
        }
    }

    static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let stride = buffer.format.isInterleaved ? channelCount : 1
        var sum = 0.0
        for channel in 0..<channelCount {
            let samples = buffer.format.isInterleaved ? channels[0].advanced(by: channel) : channels[channel]
            for index in 0..<count {
                let sample = Double(samples[index * stride])
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Double(count * channelCount))
        guard rms.isFinite, rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 55) / 45))
    }
}
