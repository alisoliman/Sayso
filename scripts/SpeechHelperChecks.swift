// Runs on macOS 27 or later via verify_speech_helpers.sh; no microphone or model assets are needed.
import AVFoundation
import CoreMedia
import Foundation
import Speech

nonisolated enum SpeechServiceError: Error { case incompatibleAudio, audioOverrun }

@main struct Validation {
 static func main() throws {
    let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    let destination = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    let converter = try SpeechAudioConverter(source: source, destination: destination)
    var totalInput = 0
    var outputDuration = CMTime.zero
    var chunks = 0
    func check(_ output: AnalyzerInput) {
      precondition(output.bufferFormat == destination)
      precondition(output.bufferStartTime == outputDuration)
      precondition(CMTimeCompare(output.bufferDuration, .zero) > 0)
      outputDuration = CMTimeAdd(outputDuration, output.bufferDuration)
      chunks += 1
    }
    while totalInput < 96_000 {
      let count = min(2_048, 96_000 - totalInput)
      let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(count))!
      buffer.frameLength = AVAudioFrameCount(count)
      for i in 0..<count { buffer.floatChannelData![0][i] = sin(Float(i + totalInput) * 0.05) * 0.25 }
      precondition(SpeechAudioConverter.normalizedLevel(buffer) > 0)
      let captured = AVReadOnlyAudioPCMBuffer(copying: buffer)
      let first = buffer.floatChannelData![0][0]
      buffer.floatChannelData![0][0] = 0.875
      let copy = AVAudioPCMBuffer(copying: captured)
      precondition(copy.floatChannelData![0][0] == first, "Read-only capture must own the audio")
      for output in try converter.convert(copy) { check(output) }
      totalInput += count
    }
    for output in try converter.flush() { check(output) }
    precondition(outputDuration == CMTime(value: 2, timescale: 1), "Conversion must not append silence or lose the final audio frames: \(outputDuration)")
    print("PASS: 96,000 captured frames converted to exactly 2 seconds at 16 kHz in \(chunks) chunks, with contiguous timestamps and independently owned PCM.")

    func range(_ start: Int64, _ duration: Int64) -> CMTimeRange {
      CMTimeRange(start: CMTime(value: start, timescale: 1), duration: CMTime(value: duration, timescale: 1))
    }
    var text = SpeechTranscriptAccumulator()
    text.replace(text: AttributedString("Hello their"), in: range(0, 2))
    text.replace(text: AttributedString("Hello there."), in: range(0, 2))
    precondition(text.text == "Hello there.")
    text.replace(text: AttributedString(" This is a draft"), in: range(2, 3))
    precondition(text.text == "Hello there. This is a draft", text.text)
    text.replace(text: AttributedString(" This is final."), in: range(2, 3))
    precondition(text.text == "Hello there. This is final.", text.text)
    text.replace(text: AttributedString(""), in: range(2, 3))
    precondition(text.text == "Hello there.", text.text)
    print("PASS: volatile revisions replace drafts; finalized prefix is retained at adjacent time boundaries; empty replacement removes withdrawn text.")

    var words = AttributedString("Hello ")
    words[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = range(0, 1)
    var oldWord = AttributedString("world")
    oldWord[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = range(1, 1)
    words.append(oldWord)
    var partial = SpeechTranscriptAccumulator()
    partial.replace(text: words, in: range(0, 2))
    var newWord = AttributedString("there")
    newWord[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = range(1, 1)
    partial.replace(text: newWord, in: range(1, 1))
    precondition(partial.text == "Hello there", partial.text)
    print("PASS: word-timed revisions preserve surrounding words.")
 }
}
