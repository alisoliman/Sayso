import AVFoundation
import XCTest
@testable import Sayso

@MainActor
final class ParakeetSpeechServiceTests: XCTestCase {
    func testPassivePreparationIsSharedWithRecordingAndRetainedAfterCancellation() async throws {
        let runtime = ControlledParakeetRuntime(suspendFirstPrepare: true)
        let permission = ParakeetPermissionGate()
        let speech = ParakeetSpeechService(runtime: runtime, requestMicrophonePermission: { await permission.wait() })
        let prewarming = Task { try await speech.prewarm(localeIdentifier: "en-US") }
        await waitUntil { await runtime.isPreparing }
        XCTAssertFalse(speech.isRecording)
        XCTAssertEqual(speech.status, "Ready")
        XCTAssertEqual(speech.partialText, "")

        let starting = Task { try await speech.start(localeIdentifier: "en-US") }
        await waitUntil { await permission.isWaiting }
        await runtime.resumePreparation()
        try await prewarming.value
        await speech.cancel()
        permission.resume()
        do {
            try await starting.value
            XCTFail("Cancelled preparation must not activate the microphone.")
        } catch { XCTAssertTrue(error is CancellationError) }

        let next = Task { try await speech.start(localeIdentifier: "nl-NL") }
        await waitUntil { await permission.isWaiting }
        await speech.cancel()
        permission.resume()
        do {
            try await next.value
            XCTFail("Cancelled preparation must not activate the microphone.")
        } catch { XCTAssertTrue(error is CancellationError) }
        let preparationCount = await runtime.prepareCalls
        XCTAssertEqual(preparationCount, 1, "The prepared model must serve repeated recording attempts and language choices.")
        let inputs = await runtime.inputs
        XCTAssertTrue(inputs.isEmpty, "Preparation and cancellation must not recognize audio.")
        XCTAssertFalse(speech.isRecording)
    }

    func testReleasingIdleModelRequiresPreparationAgain() async throws {
        let runtime = ControlledParakeetRuntime()
        let speech = ParakeetSpeechService(runtime: runtime)
        try await speech.prewarm(localeIdentifier: "en-US")
        await speech.releasePreparedResources()
        try await speech.prewarm(localeIdentifier: "nl-NL")
        let preparationCount = await runtime.prepareCalls
        let releaseCount = await runtime.releaseCalls
        XCTAssertEqual(preparationCount, 2)
        XCTAssertEqual(releaseCount, 1)
        XCTAssertFalse(speech.isRecording)
    }

    func testReleasedWarmupCannotMarkReplacementPreparationReady() async throws {
        let runtime = ControlledParakeetRuntime(suspendFirstPrepare: true)
        let speech = ParakeetSpeechService(runtime: runtime)
        let obsolete = Task { try await speech.prewarm(localeIdentifier: "en-US") }
        await waitUntil { await runtime.isPreparing }
        await speech.releasePreparedResources()
        try await speech.prewarm(localeIdentifier: "en-US")
        await runtime.resumePreparation()
        do {
            try await obsolete.value
            XCTFail("A released load must reject its late completion.")
        } catch { XCTAssertTrue(error is CancellationError) }
        try await speech.prewarm(localeIdentifier: "nl-NL")
        let preparationCount = await runtime.prepareCalls
        XCTAssertEqual(preparationCount, 2, "The late canceled completion must not invalidate the replacement model.")
    }

    func testModelLoadFailureInterruptsPendingRecordingBeforeMicrophoneActivation() async throws {
        let runtime = ControlledParakeetRuntime(suspendFirstPrepare: true, failFirstPreparation: true)
        let permission = ParakeetPermissionGate()
        let speech = ParakeetSpeechService(runtime: runtime, requestMicrophonePermission: { await permission.wait() })
        var interruptions = 0
        speech.onInterruption = { interruptions += 1 }
        let starting = Task { try await speech.start(localeIdentifier: "en-US") }
        await waitUntil { await runtime.isPreparing }
        await runtime.resumePreparation()
        await waitUntil { await speech.status == "Recording interrupted" }
        XCTAssertFalse(speech.isRecording)
        XCTAssertEqual(speech.status, "Recording interrupted")
        permission.resume()
        do {
            try await starting.value
            XCTFail("A failed model load must prevent capture and reach the caller.")
        } catch { XCTAssertTrue(error is ParakeetPreparationFailure) }
        XCTAssertEqual(interruptions, 1)
        XCTAssertEqual(speech.status, "Couldn’t transcribe")
        let inputs = await runtime.inputs
        XCTAssertTrue(inputs.isEmpty)
    }

    func testLateModelLoadFailureFromCancelledRecordingDoesNotInterruptAgain() async throws {
        let runtime = ControlledParakeetRuntime(suspendFirstPrepare: true, failFirstPreparation: true)
        let permission = ParakeetPermissionGate()
        let speech = ParakeetSpeechService(runtime: runtime, requestMicrophonePermission: { await permission.wait() })
        var interruptions = 0
        speech.onInterruption = { interruptions += 1 }
        let starting = Task { try await speech.start(localeIdentifier: "en-US") }
        await waitUntil { await runtime.isPreparing }
        await speech.cancel()
        await runtime.resumePreparation()
        permission.resume()
        do {
            try await starting.value
            XCTFail("A canceled start must not activate the microphone.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(interruptions, 0)
        XCTAssertEqual(speech.status, "Ready")
        XCTAssertFalse(speech.isRecording)
    }

    func testSameFormatConversionRetainsEverySampleAndShortTailOnce() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = try ParakeetAudioConverter(source: format)
        let chunks = [1, 137, 1_024, 333, 2_048, 541, 15]
        let count = chunks.reduce(0, +)
        let expected: [Float] = (0..<count).map { index in
            index >= count - 15 ? -0.625 : Float(index % 127) / 254
        }
        var actual: [Float] = []
        var offset = 0
        for frames in chunks {
            let buffer = try makeBuffer(format: format, frames: frames)
            for frame in 0..<frames { buffer.floatChannelData![0][frame] = expected[offset + frame] }
            let captured = AVReadOnlyAudioPCMBuffer(copying: buffer)
            for frame in 0..<frames { buffer.floatChannelData![0][frame] = 0.875 }
            actual += try converter.convert(AVAudioPCMBuffer(copying: captured))
            offset += frames
        }
        actual += try converter.flush()
        XCTAssertEqual(actual, expected, "Mutable tap reuse, irregular chunks and final drain must preserve every sample exactly once.")
        XCTAssertTrue(try converter.flush().isEmpty)
    }

    func testStereoResamplingPreservesDurationAndDistinctFinalSignal() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100, channels: 2, interleaved: true))
        let converter = try ParakeetAudioConverter(source: format)
        let chunkSizes = [1, 137, 1_024, 333, 4_096]
        var offset = 0
        var chunkIndex = 0
        var actual: [Float] = []
        while offset < 88_200 {
            let frames = min(chunkSizes[chunkIndex % chunkSizes.count], 88_200 - offset)
            let buffer = try makeBuffer(format: format, frames: frames)
            for frame in 0..<frames {
                let absoluteFrame = offset + frame
                let value: Float = absoluteFrame < 79_380 ? 0 : (absoluteFrame < 85_995 ? 0.25 : -0.375)
                buffer.floatChannelData![0][frame * 2] = value
                buffer.floatChannelData![0][frame * 2 + 1] = value
            }
            actual += try converter.convert(buffer)
            offset += frames
            chunkIndex += 1
        }
        actual += try converter.flush()
        XCTAssertEqual(actual.count, 32_000, "Resampling two seconds must neither drop the final audio nor append filter padding.")
        guard actual.count == 32_000 else { return }
        XCTAssertLessThan(actual.prefix(28_000).map { abs($0) }.max() ?? 0, 0.005)
        let positive = actual[29_120..<30_880]
        XCTAssertEqual(positive.reduce(0, +) / Float(positive.count), 0.25, accuracy: 0.02)
        let tail = actual.suffix(320)
        XCTAssertEqual(tail.reduce(0, +) / Float(tail.count), -0.375, accuracy: 0.08)
    }

    func testEmptyConverterDoesNotInventAudio() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000, channels: 1, interleaved: false))
        let converter = try ParakeetAudioConverter(source: format)
        let empty = try makeBuffer(format: format, frames: 1)
        empty.frameLength = 0
        XCTAssertTrue(try converter.convert(empty).isEmpty)
        XCTAssertTrue(try converter.flush().isEmpty)
    }

    func testStereoDownmixKeepsSpeechFromRightChannel() throws {
        for interleaved in [false, true] {
            for sampleRate in [16_000.0, 48_000.0] {
                let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                    sampleRate: sampleRate, channels: 2, interleaved: interleaved))
                let converter = try ParakeetAudioConverter(source: format)
                let frames = Int(sampleRate / 10)
                let buffer = try makeBuffer(format: format, frames: frames)
                let channels = try XCTUnwrap(buffer.floatChannelData)
                let right = interleaved ? channels[0].advanced(by: 1) : channels[1]
                let stride = interleaved ? 2 : 1
                for frame in 0..<frames {
                    channels[0][frame * stride] = 0
                    right[frame * stride] = 0.5
                }
                let samples = try converter.convert(buffer) + converter.flush()
                XCTAssertEqual(samples.count, 1_600)
                XCTAssertEqual(samples.reduce(0, +) / Float(samples.count), 0.25, accuracy: 0.01,
                               "Mono conversion must preserve the right channel at \(sampleRate) Hz, interleaved: \(interleaved).")
            }
        }
    }

    func testStereoIntegerDownmixNormalizesRightChannelForBothLayouts() throws {
        for commonFormat in [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32] {
            for interleaved in [false, true] {
                let format = try XCTUnwrap(AVAudioFormat(commonFormat: commonFormat,
                    sampleRate: 16_000, channels: 2, interleaved: interleaved))
                let converter = try ParakeetAudioConverter(source: format)
                let buffer = try makeBuffer(format: format, frames: 1_600)
                let stride = interleaved ? 2 : 1
                if commonFormat == .pcmFormatInt16 {
                    let channels = try XCTUnwrap(buffer.int16ChannelData)
                    let right = interleaved ? channels[0].advanced(by: 1) : channels[1]
                    for frame in 0..<1_600 {
                        channels[0][frame * stride] = 0
                        right[frame * stride] = 16_384
                    }
                } else {
                    let channels = try XCTUnwrap(buffer.int32ChannelData)
                    let right = interleaved ? channels[0].advanced(by: 1) : channels[1]
                    for frame in 0..<1_600 {
                        channels[0][frame * stride] = 0
                        right[frame * stride] = 1_073_741_824
                    }
                }
                let samples = try converter.convert(buffer) + converter.flush()
                XCTAssertEqual(samples, Array(repeating: 0.25, count: 1_600))
            }
        }
    }

    func testMultichannelFloat64DownmixAveragesEveryChannel() throws {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Quadraphonic))
        for interleaved in [false, true] {
            // More than two channels require an explicit channel layout.
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat64,
                sampleRate: 16_000, interleaved: interleaved, channelLayout: layout)
            let converter = try ParakeetAudioConverter(source: format)
            let buffer = try makeBuffer(format: format, frames: 1_600)
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for frame in 0..<1_600 {
                for channel in 0..<4 {
                    let data = try XCTUnwrap(buffers[interleaved ? 0 : channel].mData)
                    data.assumingMemoryBound(to: Double.self)[interleaved ? frame * 4 + channel : frame] = Double(channel + 1) / 8
                }
            }
            let samples = try converter.convert(buffer) + converter.flush()
            XCTAssertEqual(samples, Array(repeating: 0.3125, count: 1_600))
        }
    }

    func testSampleLimitAcceptsBoundaryAndRejectsOverflowBeforeMutation() throws {
        XCTAssertNoThrow(try ParakeetAudioSamples.validate(count: 9_600_000))
        XCTAssertThrowsError(try ParakeetAudioSamples.validate(count: 9_600_001)) { error in
            guard case ParakeetSpeechError.audioTooLong = error else { return XCTFail("Unexpected error: \(error)") }
        }
        var samples = ParakeetAudioSamples()
        try samples.append(Array(repeating: 0.25, count: ParakeetAudioSamples.maximumCount))
        XCTAssertThrowsError(try samples.append([-0.5]))
        XCTAssertEqual(samples.values.count, ParakeetAudioSamples.maximumCount)
        XCTAssertEqual(samples.values.last, 0.25)
    }

    func testTenMinuteResamplingFitsExactSampleLimitIncludingFlush() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000, channels: 1, interleaved: false))
        let converter = try ParakeetAudioConverter(source: format)
        let buffer = try makeBuffer(format: format, frames: 48_000)
        for frame in 0..<48_000 { buffer.floatChannelData![0][frame] = 0 }
        var samples = ParakeetAudioSamples()
        for _ in 0..<600 { try samples.append(converter.convert(buffer)) }
        try samples.append(converter.flush())
        XCTAssertEqual(samples.values.count, ParakeetAudioSamples.maximumCount,
                       "A valid ten-minute recording must still fit after draining the resampler.")
    }

    private func makeBuffer(format: AVAudioFormat, frames: Int) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Runtime did not reach the expected suspension point.", file: file, line: line)
    }
}

private actor ControlledParakeetRuntime: ParakeetRecognizing {
    private let suspendFirstPrepare: Bool
    private let failFirstPreparation: Bool
    private var preparation: CheckedContinuation<Void, Never>?
    private(set) var prepareCalls = 0
    private(set) var releaseCalls = 0
    private(set) var inputs: [[Float]] = []
    var isPreparing: Bool { preparation != nil }

    init(suspendFirstPrepare: Bool = false, failFirstPreparation: Bool = false) {
        self.suspendFirstPrepare = suspendFirstPrepare
        self.failFirstPreparation = failFirstPreparation
    }

    func prepare() async throws {
        prepareCalls += 1
        if suspendFirstPrepare, prepareCalls == 1 { await withCheckedContinuation { preparation = $0 } }
        if failFirstPreparation, prepareCalls == 1 { throw ParakeetPreparationFailure.unavailable }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        inputs.append(samples)
        return "  result \(inputs.count)\n"
    }

    func releasePreparedResources() async { releaseCalls += 1 }

    func resumePreparation() { preparation?.resume(); preparation = nil }
}

private enum ParakeetPreparationFailure: Error { case unavailable }

@MainActor
private final class ParakeetPermissionGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async -> Bool { await withCheckedContinuation { continuation = $0 } }
    func resume() {
        continuation?.resume(returning: true)
        continuation = nil
    }
}
