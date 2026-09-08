import AVFoundation
import XCTest
@testable import Sayso

@MainActor
final class ParakeetSpeechServiceTests: XCTestCase {
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

    func testStereoInt16WAVImportRetainsRightChannelAfterResampling() throws {
        let url = URL.temporaryDirectory.appending(path: "ParakeetStereo-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16,
            sampleRate: 48_000, channels: 2, interleaved: true))
        let buffer = try makeBuffer(format: format, frames: 24_000)
        let samples = try XCTUnwrap(buffer.int16ChannelData)[0]
        for frame in 0..<24_000 {
            samples[frame * 2] = 0
            samples[frame * 2 + 1] = frame < 21_600 ? 16_384 : -24_576
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                       commonFormat: .pcmFormatInt16, interleaved: true)
            try file.write(from: buffer)
        }
        let converted = try ParakeetAudioConverter.readFile(at: url)
        XCTAssertEqual(converted.count, 8_000)
        guard converted.count == 8_000 else { return }
        let speech = converted[160..<7_040]
        XCTAssertEqual(speech.reduce(0, +) / Float(speech.count), 0.25, accuracy: 0.01)
        let tail = converted.suffix(160)
        XCTAssertEqual(tail.reduce(0, +) / Float(tail.count), -0.375, accuracy: 0.04)
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

    func testTooShortAudioReturnsActionableErrorWithoutCallingInference() async {
        let runtime = ControlledParakeetRuntime()
        let speech = ParakeetSpeechService(runtime: runtime, fileLoader: { _ in Array(repeating: 0, count: 4_799) })
        do {
            _ = try await speech.transcribeFile(at: URL(filePath: "/short.wav"), localeIdentifier: "en-US")
            XCTFail("The runtime requires at least 0.3 seconds of audio.")
        } catch {
            guard case ParakeetSpeechError.audioTooShort = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let inputs = await runtime.inputs
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertEqual(speech.partialText, "")
    }

    func testImportedAudioIsConvertedBeforeOneLocalRecognition() async throws {
        let url = URL.temporaryDirectory.appending(path: "ParakeetImport-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000, channels: 1, interleaved: false))
        let buffer = try makeBuffer(format: format, frames: 24_000)
        for frame in 0..<24_000 { buffer.floatChannelData![0][frame] = frame < 21_600 ? 0.25 : -0.375 }
        try writeAudio(buffer, at: url)
        let runtime = ControlledParakeetRuntime()
        let speech = ParakeetSpeechService(runtime: runtime)

        let result = try await speech.transcribeFile(at: url, localeIdentifier: "nl-NL", contextualStrings: ["Sayso"])
        XCTAssertEqual(result, "result 1")
        XCTAssertEqual(speech.partialText, result)
        XCTAssertFalse(speech.isRecording)
        XCTAssertEqual(speech.status, "Ready")
        let received = await runtime.inputs
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.count, 8_000)
        let tail = try XCTUnwrap(received.first).suffix(160)
        XCTAssertEqual(tail.reduce(0, +) / Float(tail.count), -0.375, accuracy: 0.08)
        let prepareCalls = await runtime.prepareCalls
        XCTAssertEqual(prepareCalls, 1)
    }

    func testOversizedFileFailsBeforeLoadingLocalModel() async throws {
        let url = URL.temporaryDirectory.appending(path: "ParakeetLong-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        // A sparse valid PCM WAV exercises AVAudioFile's actual frame count
        // without allocating or writing ten minutes of fixture audio.
        try writeSparseWAV(at: url, frames: UInt32(ParakeetAudioSamples.maximumCount + 1))
        let runtime = ControlledParakeetRuntime()
        let speech = ParakeetSpeechService(runtime: runtime)
        do {
            _ = try await speech.transcribeFile(at: url, localeIdentifier: "en-US")
            XCTFail("An oversized import must fail before decoding or loading the model.")
        } catch {
            guard case ParakeetSpeechError.audioTooLong = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let prepareCalls = await runtime.prepareCalls
        let inputs = await runtime.inputs
        XCTAssertEqual(prepareCalls, 0)
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertEqual(speech.partialText, "")
        XCTAssertEqual(speech.status, "Couldn’t transcribe")
    }

    func testCancelledPreparationCannotOverwriteSubsequentResultOrDiagnostics() async throws {
        let runtime = ControlledParakeetRuntime(suspendFirstPrepare: true)
        let speech = ParakeetSpeechService(runtime: runtime, fileLoader: { _ in Array(repeating: 0.1, count: 4_800) })
        let first = Task { try await speech.transcribeFile(at: URL(filePath: "/first.wav"), localeIdentifier: "en-US") }
        await waitUntil { await runtime.isPreparing }
        do {
            _ = try await speech.transcribeFile(at: URL(filePath: "/busy.wav"), localeIdentifier: "en-US")
            XCTFail("Concurrent sessions must be rejected.")
        } catch {
            guard case SpeechServiceError.busy = error else { return XCTFail("Unexpected error: \(error)") }
        }
        await speech.cancel()
        XCTAssertEqual(speech.status, "Ready")
        let latest = try await speech.transcribeFile(at: URL(filePath: "/second.wav"), localeIdentifier: "nl-NL")
        let latestDiagnostics = speech.diagnosticsReport
        await runtime.resumePreparation()
        do {
            _ = try await first.value
            XCTFail("A cancelled prepare must not proceed to recognition.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(speech.partialText, latest)
        XCTAssertEqual(speech.diagnosticsReport, latestDiagnostics)
        XCTAssertEqual(speech.status, "Ready")
        let inputs = await runtime.inputs
        XCTAssertEqual(inputs.count, 1)
    }

    func testLateRecognitionFromCancelledSessionCannotPublishStaleWords() async throws {
        let runtime = ControlledParakeetRuntime(suspendFirstRecognition: true)
        let speech = ParakeetSpeechService(runtime: runtime, fileLoader: { _ in Array(repeating: 0.25, count: 4_800) })
        let first = Task { try await speech.transcribeFile(at: URL(filePath: "/first.wav"), localeIdentifier: "en-US") }
        await waitUntil { await runtime.isRecognizing }
        XCTAssertEqual(speech.partialText, "", "Batch recognition must not pretend to produce live text.")
        await speech.cancel()
        let latest = try await speech.transcribeFile(at: URL(filePath: "/second.wav"), localeIdentifier: "en-US")
        await runtime.resumeRecognition()
        do {
            _ = try await first.value
            XCTFail("Cancelled recognition must not publish its late result.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(latest, "result 2")
        XCTAssertEqual(speech.partialText, latest)
        XCTAssertEqual(speech.status, "Ready")
    }

    private func makeBuffer(format: AVAudioFormat, frames: Int) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    private func writeAudio(_ buffer: AVAudioPCMBuffer, at url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
    }

    private func writeSparseWAV(at url: URL, frames: UInt32) throws {
        let bytes = frames * 2
        var header = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            Swift.withUnsafeBytes(of: &little) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: "RIFF".utf8); word(bytes + 36)
        header.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16))
        word(UInt16(1)); word(UInt16(1)); word(UInt32(16_000)); word(UInt32(32_000))
        word(UInt16(2)); word(UInt16(16))
        header.append(contentsOf: "data".utf8); word(bytes)
        try header.write(to: url)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.truncate(atOffset: UInt64(bytes) + 44)
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
    private let suspendFirstRecognition: Bool
    private var preparation: CheckedContinuation<Void, Never>?
    private var recognition: CheckedContinuation<String, Never>?
    private(set) var prepareCalls = 0
    private(set) var inputs: [[Float]] = []
    var isPreparing: Bool { preparation != nil }
    var isRecognizing: Bool { recognition != nil }

    init(suspendFirstPrepare: Bool = false, suspendFirstRecognition: Bool = false) {
        self.suspendFirstPrepare = suspendFirstPrepare
        self.suspendFirstRecognition = suspendFirstRecognition
    }

    func prepare() async throws {
        prepareCalls += 1
        if suspendFirstPrepare, prepareCalls == 1 { await withCheckedContinuation { preparation = $0 } }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        inputs.append(samples)
        if suspendFirstRecognition, inputs.count == 1 {
            return await withCheckedContinuation { recognition = $0 }
        }
        return "  result \(inputs.count)\n"
    }

    func resumePreparation() { preparation?.resume(); preparation = nil }
    func resumeRecognition() { recognition?.resume(returning: "stale words"); recognition = nil }
}
