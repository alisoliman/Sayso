import XCTest
@testable import Sayso

final class SpeechDiagnosticsTests: XCTestCase {
    func testCaptureAndConversionAggregateDifferentBufferBoundaries() {
        var diagnostic = SpeechDiagnostics()
        diagnostic.observeCapture(frames: 4_800, level: 0.2)
        diagnostic.observeCapture(frames: 2_400, level: 0.7)
        diagnostic.observeCapture(frames: 128, level: 0.1)
        diagnostic.observeConverted(duration: 0.1)
        diagnostic.observeConverted(duration: 0.05)
        diagnostic.observeConverted(duration: 128.0 / 48_000)

        XCTAssertEqual(diagnostic.captureBuffers, 3)
        XCTAssertEqual(diagnostic.captureFrames, 7_328)
        XCTAssertEqual(diagnostic.convertedBuffers, 3)
        XCTAssertEqual(diagnostic.convertedSeconds, 7_328.0 / 48_000, accuracy: 0.000_001)
        XCTAssertEqual(diagnostic.peakLevel, 0.7)
    }

    func testEmptyAndInvalidAudioObservationsDoNotInventDeliveredAudio() {
        var diagnostic = SpeechDiagnostics()
        diagnostic.observeCapture(frames: 0, level: 1)
        diagnostic.observeCapture(frames: -1, level: 1)
        for duration in [0, -1, Double.nan, .infinity, -.infinity] {
            diagnostic.observeConverted(duration: duration)
        }
        XCTAssertEqual(diagnostic.captureBuffers, 0)
        XCTAssertEqual(diagnostic.captureFrames, 0)
        XCTAssertEqual(diagnostic.peakLevel, 0)
        XCTAssertEqual(diagnostic.convertedBuffers, 0)
        XCTAssertEqual(diagnostic.convertedSeconds, 0)

        // Invalid metering cannot hide delivery of a real buffer.
        diagnostic.observeCapture(frames: 64, level: .nan)
        diagnostic.observeCapture(frames: 64, level: .infinity)
        diagnostic.observeCapture(frames: 64, level: -3)
        XCTAssertEqual(diagnostic.captureFrames, 192)
        XCTAssertEqual(diagnostic.captureBuffers, 3)
        XCTAssertEqual(diagnostic.peakLevel, 0)
        diagnostic.observeCapture(frames: 64, level: 4)
        XCTAssertEqual(diagnostic.peakLevel, 1)
    }

    func testResultRevisionsPreserveHighWaterMarkAndFinalLossEvidence() {
        var diagnostic = SpeechDiagnostics()
        diagnostic.observeResult(characters: 12, accumulatedCharacters: 12)
        diagnostic.observeResult(characters: 8, accumulatedCharacters: 8)
        diagnostic.observeResult(characters: 0, accumulatedCharacters: 0)
        diagnostic.finish(characters: 0, outcome: "empty", stopReason: "userStop")

        XCTAssertEqual(diagnostic.resultCount, 3)
        XCTAssertEqual(diagnostic.nonemptyResultCount, 2)
        XCTAssertEqual(diagnostic.maxTranscriptCharacters, 12)
        XCTAssertEqual(diagnostic.finalCharacters, 0,
                       "An earlier nonempty result must not mask an empty final transcript.")
        XCTAssertEqual(diagnostic.outcome, "empty")
        XCTAssertEqual(diagnostic.stopReason, "userStop")
    }

    func testEmptyResultsRemainDistinctFromNoResultsAndNegativeCountsClamp() {
        var diagnostic = SpeechDiagnostics()
        diagnostic.observeResult(characters: 0, accumulatedCharacters: 0)
        diagnostic.observeResult(characters: -1, accumulatedCharacters: -3)
        diagnostic.finish(characters: -1, outcome: "interrupted", stopReason: "audioInactive")

        XCTAssertEqual(diagnostic.resultCount, 2)
        XCTAssertEqual(diagnostic.nonemptyResultCount, 0)
        XCTAssertEqual(diagnostic.maxTranscriptCharacters, 0)
        XCTAssertEqual(diagnostic.finalCharacters, 0)
        XCTAssertTrue(diagnostic.renderReport().contains("Stop reason: audioInactive"))
    }

    func testReportUsesInjectedMetadataAndCountsWithoutReceivingContent() {
        var diagnostic = SpeechDiagnostics(localeIdentifier: "nl-NL", appVersion: "1.2",
                                           appBuild: "42", osVersion: "27.0 (24A5423a)")
        diagnostic.inputPortTypes = ["MicrophoneBuiltIn"]
        diagnostic.captureFormat = "48000 Hz, 1 channel, Float32"
        diagnostic.analyzerFormat = "16000 Hz, 1 channel, Int16"
        diagnostic.observeCapture(frames: 4_800, level: 0.25)
        diagnostic.observeConverted(duration: 0.1)
        diagnostic.observeResult(characters: 12, accumulatedCharacters: 12)
        diagnostic.analyzerLastSampleSeconds = 0.1
        diagnostic.finish(characters: 12, outcome: "completed", stopReason: "userStop")
        let report = diagnostic.renderReport()

        for expected in ["App version: 1.2", "App build: 42", "OS version: 27.0 (24A5423a)",
                         "Speech language: nl-NL", "Input port types: MicrophoneBuiltIn",
                         "Capture frames: 4800", "Converted seconds: 0.100",
                         "Peak normalized level: 0.250", "Final characters: 12",
                         "Analyzer last sample seconds: 0.100"] {
            XCTAssertTrue(report.contains(expected), expected)
        }
        // The diagnostic API receives counts, not source words or PCM samples.
        XCTAssertEqual(report.components(separatedBy: "\n").count, 20)
        XCTAssertFalse(report.contains("userInfo"))
        XCTAssertFalse(report.contains("routeUID"))
    }

    func testUnknownAndInvalidAnalyzerTimeReportUnavailableWithoutLeakingPriorAttempt() {
        var first = SpeechDiagnostics()
        first.observeCapture(frames: 100, level: 0.4)
        first.observeResult(characters: 9, accumulatedCharacters: 9)
        first.finish(characters: 9, outcome: "completed", stopReason: "userStop")

        var next = SpeechDiagnostics()
        XCTAssertEqual(next.captureFrames, 0)
        XCTAssertEqual(next.resultCount, 0)
        XCTAssertEqual(next.finalCharacters, 0)
        XCTAssertEqual(next.stopReason, "unknown", "The service fills the actual stop cause later.")
        XCTAssertTrue(next.renderReport().contains("App build: unknown"))
        for time in [nil, Double.nan, .infinity, -1] as [Double?] {
            next.analyzerLastSampleSeconds = time
            XCTAssertTrue(next.renderReport().contains("Analyzer last sample seconds: unavailable"))
        }
        next.analyzerLastSampleSeconds = 0
        XCTAssertTrue(next.renderReport().contains("Analyzer last sample seconds: 0.000"))
        XCTAssertEqual(first.finalCharacters, 9, "A new attempt must be an independent value.")
    }

    func testEmptyRecordingErrorsIdentifyStageWithoutBlamingMicrophoneDistance() {
        let stages: [(SpeechServiceError, String)] = [
            (.noAudioCaptured, "didn’t receive audio"),
            (.audioNotConverted, "couldn’t be converted"),
            (.audioNotAnalyzed, "didn’t process"),
            (.noWordsRecognized("nl-NL"), "no words were transcribed")
        ]
        var messages = Set<String>()
        for (error, stage) in stages {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains(stage), "The error must distinguish the failed stage.")
            XCTAssertFalse(message.localizedCaseInsensitiveContains("closer"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("too quiet"))
            messages.insert(message)
        }
        XCTAssertEqual(messages.count, 4)
    }
}
