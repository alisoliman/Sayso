import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Accessed exclusively by one detached task, never by the audio tap or UI.
/// AnalyzerInputConverter has no public Sendable conformance. This unchecked
/// wrapper preserves the existing exclusive ownership transfer into that task;
/// it does not permit concurrent access to the converter or its input buffers.
@available(iOS 27.0, macOS 27.0, tvOS 27.0, visionOS 27.0, *)
nonisolated final class SpeechAudioConverter: @unchecked Sendable {
    private let converter: AnalyzerInputConverter
    private let source: AVAudioFormat

    init(source: AVAudioFormat, destination: AVAudioFormat) throws {
        guard destination.commonFormat == .pcmFormatInt16 else {
            throw SpeechServiceError.incompatibleAudio
        }
        self.source = source
        converter = AnalyzerInputConverter(analyzerFormat: destination) { converter in
            // Normal priming keeps filter latency out of the output timeline.
            // The native converter supplies and drains the required trailing input.
            converter.primeMethod = .normal
        }
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> [AnalyzerInput] {
        guard input.format == source else { throw SpeechServiceError.incompatibleAudio }
        guard input.frameLength > 0 else { return [] }
        return try converter.convert(input, at: nil)
    }

    func flush() throws -> [AnalyzerInput] {
        try converter.flush()
    }
}

nonisolated extension AVAudioPCMBuffer {
    /// Both speech providers use the same meter for captured microphone audio.
    var normalizedSpeechLevel: Double {
        guard let channels = floatChannelData, frameLength > 0 else { return 0 }
        let sampleCount = Int(frameLength)
        let channelCount = Int(format.channelCount)
        let stride = format.isInterleaved ? channelCount : 1
        var sum = 0.0
        for channel in 0..<channelCount {
            let samples = format.isInterleaved ? channels[0].advanced(by: channel) : channels[channel]
            for index in 0..<sampleCount {
                let sample = Double(samples[index * stride])
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Double(sampleCount * channelCount))
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 55) / 45))
    }
}
