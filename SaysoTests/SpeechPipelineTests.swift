import AVFoundation
import CoreMedia
import Speech
import XCTest
@testable import Sayso

@MainActor
final class SpeechPipelineTests: XCTestCase {
    private func range(_ start: Int64, _ duration: Int64) -> CMTimeRange {
        CMTimeRange(start: CMTime(value: start, timescale: 1), duration: CMTime(value: duration, timescale: 1))
    }

    func testReadOnlyAudioOwnsItsSamplesAfterTapBufferChanges() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        source.frameLength = 128
        for index in 0..<128 { source.floatChannelData![0][index] = 0.25 }
        let captured = AVReadOnlyAudioPCMBuffer(copying: source)
        source.floatChannelData![0][0] = -0.75
        let received = AVAudioPCMBuffer(copying: captured)

        XCTAssertEqual(received.frameLength, 128)
        XCTAssertEqual(received.floatChannelData![0][0], 0.25)
        XCTAssertGreaterThan(received.normalizedSpeechLevel, 0)
    }

    func testSharedMeterPreservesLevelAcrossMicrophoneChannelLayouts() throws {
        for interleaved in [false, true] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000, channels: 2, interleaved: interleaved))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
            XCTAssertEqual(buffer.normalizedSpeechLevel, 0)
            buffer.frameLength = 128
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0..<2 {
                let samples = interleaved ? channels[0].advanced(by: channel) : channels[channel]
                for frame in 0..<128 { samples[frame * (interleaved ? 2 : 1)] = 0.1 }
            }
            // A -20 dB signal should retain the same visible level in either layout.
            XCTAssertEqual(buffer.normalizedSpeechLevel, 35.0 / 45.0, accuracy: 0.000_001)
            channels[0][0] = .nan
            XCTAssertEqual(buffer.normalizedSpeechLevel, 0)
        }
    }

    func testConversionPreservesDurationAndContinuousTimestampsThroughFlush() throws {
        let source = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let destination = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = try SpeechAudioConverter(source: source, destination: destination)
        var inputFrames = 0
        var outputDuration = CMTime.zero

        func inspect(_ output: AnalyzerInput) {
            XCTAssertEqual(output.bufferFormat, destination)
            XCTAssertEqual(output.bufferStartTime, outputDuration)
            XCTAssertGreaterThan(CMTimeCompare(output.bufferDuration, .zero), 0)
            outputDuration = CMTimeAdd(outputDuration, output.bufferDuration)
        }

        // Two seconds split at microphone tap boundaries, including a short final chunk.
        while inputFrames < 96_000 {
            let frames = min(2_048, 96_000 - inputFrames)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(frames)))
            buffer.frameLength = AVAudioFrameCount(frames)
            for index in 0..<frames {
                buffer.floatChannelData![0][index] = sin(Float(inputFrames + index) * 0.05) * 0.25
            }
            for output in try converter.convert(buffer) { inspect(output) }
            inputFrames += frames
        }
        for output in try converter.flush() { inspect(output) }
        XCTAssertEqual(outputDuration, CMTime(value: 2, timescale: 1), "Conversion must not append silence or lose the final audio frames.")
    }

    func testConversionHandlesInterleavedStereoAndIrregularChunks() throws {
        let source = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: true))
        let destination = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        try inspectConversion(source: source, destination: destination, totalFrames: 22_050)
    }

    func testConversionKeepsSameFormatAudioContinuousThroughFinalDrain() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: false))
        try inspectConversion(source: format, destination: format, totalFrames: 24_000)
    }

    func testSameFormatConversionPreservesEverySampleAndUniqueShortTail() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: false))
        let converter = try SpeechAudioConverter(source: format, destination: format)
        let chunkSizes = [1, 137, 1_024, 333, 2_048, 541, 15]
        let totalFrames = chunkSizes.reduce(0, +)
        let expected: [Int16] = (0..<totalFrames).map { frame in
            // The final 15 samples are outside the earlier signal's amplitude range.
            if frame >= totalFrames - 15 { return Int16(16_000 + (frame - (totalFrames - 15)) * 503) }
            return Int16((frame * 37) % 2_047 - 1_023)
        }
        var actual: [Int16] = []
        var endTime = CMTime.zero
        func collect(_ inputs: [AnalyzerInput]) throws {
            for input in inputs {
                XCTAssertEqual(input.bufferFormat, format)
                XCTAssertEqual(input.bufferStartTime, endTime)
                XCTAssertGreaterThan(CMTimeCompare(input.bufferDuration, .zero), 0)
                endTime = CMTimeAdd(endTime, input.bufferDuration)
                let pcm = pcmForSampleAssertions(input)
                let channels = try XCTUnwrap(pcm.int16ChannelData)
                actual.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: Int(pcm.frameLength)))
            }
        }
        var offset = 0
        for count in chunkSizes {
            let tapBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
            tapBuffer.frameLength = AVAudioFrameCount(count)
            for frame in 0..<count { tapBuffer.int16ChannelData![0][frame] = expected[offset + frame] }
            let captured = AVReadOnlyAudioPCMBuffer(copying: tapBuffer)
            // Simulate reuse of the tap's mutable memory before the consumer receives it.
            for frame in 0..<count { tapBuffer.int16ChannelData![0][frame] = -28_000 }
            try collect(converter.convert(AVAudioPCMBuffer(copying: captured)))
            offset += count
        }
        try collect(converter.flush())
        XCTAssertEqual(endTime, CMTime(value: Int64(totalFrames), timescale: 48_000))
        XCTAssertEqual(actual.count, expected.count, "Every captured sample, including the short tail, must survive exactly once.")
        if let mismatch = zip(actual, expected).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
            XCTFail("Converted sample \(mismatch.offset) is \(mismatch.element.0), expected \(mismatch.element.1).")
        }
    }

    func testResamplingPreservesSustainedFinalSignalThroughFlush() throws {
        let source = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let destination = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = try SpeechAudioConverter(source: source, destination: destination)
        let chunkSizes = [1, 137, 1_024, 333, 4_096]
        var capturedFrames = 0
        var chunkIndex = 0
        var endTime = CMTime.zero
        var samples: [Double] = []
        func collect(_ inputs: [AnalyzerInput]) throws {
            for input in inputs {
                XCTAssertEqual(input.bufferFormat, destination)
                XCTAssertEqual(input.bufferStartTime, endTime)
                XCTAssertGreaterThan(CMTimeCompare(input.bufferDuration, .zero), 0)
                endTime = CMTimeAdd(endTime, input.bufferDuration)
                let pcm = pcmForSampleAssertions(input)
                let channels = try XCTUnwrap(pcm.int16ChannelData)
                for frame in 0..<Int(pcm.frameLength) { samples.append(Double(channels[0][frame]) / 32_768) }
            }
        }
        while capturedFrames < 96_000 {
            let count = min(chunkSizes[chunkIndex % chunkSizes.count], 96_000 - capturedFrames)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            for frame in 0..<count {
                let absoluteFrame = capturedFrames + frame
                // Silence for 1.8 s, then +0.25; the last 50 ms is a distinct -0.375 tail.
                buffer.floatChannelData![0][frame] = absoluteFrame < 86_400 ? 0 : (absoluteFrame < 93_600 ? 0.25 : -0.375)
            }
            try collect(converter.convert(buffer))
            capturedFrames += count
            chunkIndex += 1
        }
        try collect(converter.flush())
        XCTAssertEqual(endTime, CMTime(value: 2, timescale: 1))
        guard samples.count == 32_000 else {
            XCTFail("Expected 32,000 resampled frames, received \(samples.count).")
            return
        }
        let quietPeak = samples[..<28_000].map { abs($0) }.max() ?? 0
        XCTAssertLessThan(quietPeak, 0.005, "The silent prefix must not contain replayed tail audio.")
        let positiveWindow = samples[29_120..<30_880] // 1.82–1.93 s, away from filter transitions.
        XCTAssertEqual(positiveWindow.reduce(0, +) / Double(positiveWindow.count), 0.25, accuracy: 0.02)
        let finalWindow = samples.suffix(320) // Last 20 ms, including the recording's final samples.
        // Allow filter-edge settling and Int16 quantization, while rejecting a silent or replayed positive tail.
        XCTAssertEqual(finalWindow.reduce(0, +) / Double(finalWindow.count), -0.375, accuracy: 0.08)
    }

    func testInitialFlushWithoutCapturedAudioProducesNoInput() throws {
        let source = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let destination = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let fresh = try SpeechAudioConverter(source: source, destination: destination)
        XCTAssertTrue(try fresh.flush().isEmpty, "Stopping before the first tap must not invent audio or fail to drain.")

        let empty = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 1))
        empty.frameLength = 0
        let afterEmptyInput = try SpeechAudioConverter(source: source, destination: destination)
        XCTAssertTrue(try afterEmptyInput.convert(empty).isEmpty)
        XCTAssertTrue(try afterEmptyInput.flush().isEmpty)
    }

    func testUnsupportedAnalyzerFormatFailsBeforeNativePrecondition() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        XCTAssertThrowsError(try SpeechAudioConverter(source: format, destination: format)) { error in
            guard case SpeechServiceError.incompatibleAudio = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func pcmForSampleAssertions(_ input: AnalyzerInput) -> AVAudioPCMBuffer {
        // Test-only use of the deprecated PCM-copy getter: metadata cannot detect lost or duplicated samples.
        // Keep its warning visible; production and metadata checks use the native format/duration properties.
        input.buffer
    }

    private func inspectConversion(source: AVAudioFormat, destination: AVAudioFormat, totalFrames: Int) throws {
        let converter = try SpeechAudioConverter(source: source, destination: destination)
        let chunkSizes = [1, 137, 1_024, 333, 4_096]
        var capturedFrames = 0
        var chunkIndex = 0
        var endTime = CMTime.zero
        func inspect(_ input: AnalyzerInput) {
            XCTAssertEqual(input.bufferFormat, destination)
            XCTAssertEqual(input.bufferStartTime, endTime)
            XCTAssertGreaterThan(CMTimeCompare(input.bufferDuration, .zero), 0)
            endTime = CMTimeAdd(endTime, input.bufferDuration)
        }
        while capturedFrames < totalFrames {
            let count = min(chunkSizes[chunkIndex % chunkSizes.count], totalFrames - capturedFrames)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            let channels = Int(source.channelCount)
            for frame in 0..<count {
                for channel in 0..<channels {
                    let offset = source.isInterleaved ? frame * channels + channel : frame
                    let amplitude = sin(Float(capturedFrames + frame + 1) * 0.05) * Float(channel + 1) * 0.125
                    // Capture fixtures use Float32; same-format analyzer fixtures require Int16.
                    if source.commonFormat == .pcmFormatInt16 {
                        let planes = try XCTUnwrap(buffer.int16ChannelData)
                        let samples = source.isInterleaved ? planes[0] : planes[channel]
                        samples[offset] = Int16((amplitude * Float(Int16.max)).rounded())
                    } else {
                        let planes = try XCTUnwrap(buffer.floatChannelData)
                        let samples = source.isInterleaved ? planes[0] : planes[channel]
                        samples[offset] = amplitude
                    }
                }
            }
            let owned = AVReadOnlyAudioPCMBuffer(copying: buffer)
            for input in try converter.convert(AVAudioPCMBuffer(copying: owned)) { inspect(input) }
            capturedFrames += count
            chunkIndex += 1
        }
        for input in try converter.flush() { inspect(input) }
        XCTAssertEqual(endTime, CMTime(value: Int64(totalFrames), timescale: CMTimeScale(source.sampleRate)), "Irregular capture chunks must preserve the complete recording duration.")
    }

    func testVolatileRevisionsAndWithdrawalsRetainFinalizedPrefix() {
        var transcript = SpeechTranscriptAccumulator()
        transcript.replace(text: AttributedString("Hello their"), in: range(0, 2))
        transcript.replace(text: AttributedString("Hello there."), in: range(0, 2))
        XCTAssertEqual(transcript.text, "Hello there.")
        transcript.replace(text: AttributedString(" This is a draft"), in: range(2, 3))
        transcript.replace(text: AttributedString(" This is final."), in: range(2, 3))
        XCTAssertEqual(transcript.text, "Hello there. This is final.")
        transcript.replace(text: AttributedString(""), in: range(2, 3))
        XCTAssertEqual(transcript.text, "Hello there.")
    }

    func testWordTimedRevisionPreservesSurroundingWords() {
        typealias AudioTime = AttributeScopes.SpeechAttributes.TimeRangeAttribute
        var phrase = AttributedString("Hello ")
        phrase[AudioTime.self] = range(0, 1)
        var oldWord = AttributedString("world")
        oldWord[AudioTime.self] = range(1, 1)
        phrase.append(oldWord)
        var transcript = SpeechTranscriptAccumulator()
        transcript.replace(text: phrase, in: range(0, 2))
        var replacement = AttributedString("there")
        replacement[AudioTime.self] = range(1, 1)
        transcript.replace(text: replacement, in: range(1, 1))
        XCTAssertEqual(transcript.text, "Hello there")
    }
}
