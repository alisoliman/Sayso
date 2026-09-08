import Foundation

/// A content-free snapshot owned by one recording task. It stores no audio,
/// transcript, vocabulary, route name/UID, error userInfo, or persistent identity.
/// Metadata must be system identifiers and numeric format descriptions only.
nonisolated struct SpeechDiagnostics: Sendable {
    var localeIdentifier: String
    var inputPortTypes: [String] = []
    var captureFormat = "unknown"
    var analyzerFormat = "unknown"
    var outcome = "notFinished"
    var stopReason = "unknown"
    var analyzerLastSampleSeconds: Double?
    var appVersion: String
    var appBuild: String
    var osVersion: String

    private(set) var captureFrames = 0
    private(set) var captureBuffers = 0
    private(set) var convertedBuffers = 0
    private(set) var convertedSeconds = 0.0
    private(set) var peakLevel = 0.0
    private(set) var resultCount = 0
    private(set) var nonemptyResultCount = 0
    private(set) var maxTranscriptCharacters = 0
    private(set) var finalCharacters = 0

    init(localeIdentifier: String = "unknown", appVersion: String = "unknown",
         appBuild: String = "unknown", osVersion: String = "unknown") {
        self.localeIdentifier = localeIdentifier
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.osVersion = osVersion
    }

    /// Counts nonempty PCM buffers. Level is an aggregate supplied by the
    /// consumer; no sample data enters this value or its report.
    mutating func observeCapture(frames: Int, level: Double) {
        guard frames > 0 else { return }
        captureBuffers += 1
        captureFrames += frames
        if level.isFinite { peakLevel = max(peakLevel, min(1, max(0, level))) }
    }

    /// Call for each actual analyzer input, including final converter flushes.
    mutating func observeConverted(duration: Double) {
        guard duration.isFinite, duration > 0,
              (convertedSeconds + duration).isFinite else { return }
        convertedBuffers += 1
        convertedSeconds += duration
    }

    /// A result can revise an earlier phrase. Track its event separately from
    /// the accumulated character high-water mark; never accept the text itself.
    mutating func observeResult(characters: Int, accumulatedCharacters: Int) {
        resultCount += 1
        if characters > 0 { nonemptyResultCount += 1 }
        maxTranscriptCharacters = max(maxTranscriptCharacters, max(0, accumulatedCharacters))
    }

    mutating func finish(characters: Int, outcome: String, stopReason: String) {
        finalCharacters = max(0, characters)
        self.outcome = outcome
        self.stopReason = stopReason
    }

    func renderReport() -> String {
        let lastSample = analyzerLastSampleSeconds.flatMap { seconds in
            seconds.isFinite && seconds >= 0 ? decimal(seconds) : nil
        } ?? "unavailable"
        return """
        Sayso speech diagnostics
        App version: \(appVersion)
        App build: \(appBuild)
        OS version: \(osVersion)
        Speech language: \(localeIdentifier)
        Input port types: \(inputPortTypes.isEmpty ? "unknown" : inputPortTypes.joined(separator: ", "))
        Capture format: \(captureFormat)
        Analyzer format: \(analyzerFormat)
        Outcome: \(outcome)
        Stop reason: \(stopReason)
        Capture buffers: \(captureBuffers)
        Capture frames: \(captureFrames)
        Converted buffers: \(convertedBuffers)
        Converted seconds: \(decimal(convertedSeconds))
        Peak normalized level: \(decimal(peakLevel))
        Result events: \(resultCount)
        Nonempty result events: \(nonemptyResultCount)
        Maximum transcript characters: \(maxTranscriptCharacters)
        Final characters: \(finalCharacters)
        Analyzer last sample seconds: \(lastSample)
        """
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
