import Foundation
import Observation
import UIKit

@MainActor @Observable
final class DictationController {
    enum Phase: Equatable { case idle, preparing, recording, finishing, refining }
    typealias Transformation = @MainActor (String, WritingMode, String, [String]) async throws -> String

    let speech: any SpeechTranscribing
    let intelligence: IntelligenceService
    let store: DictationStore
    let speechModels: ParakeetModelStore
    var phase: Phase = .idle
    var current: Dictation?
    var notice: String?
    var resultNote: String?
    var startedAt: Date?
    var copied = false
    @ObservationIgnored private let transformation: Transformation
    @ObservationIgnored private let usesSystemWritingModel: Bool
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var resourceReleaseTask: Task<Void, Never>?
    private var isInBackground = false
    private var releaseWhenIdle = false
    private var preparationSuppressedForMemoryPressure = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var backgroundGeneration: UUID?
    private var generation = UUID()
    private var activeStyle = WritingStyle.defaults[0]
    private var activeLocale = "en-US"
    private var activeVocabulary: [String] = []
    private var activeDictationID = UUID()
    private var activeCreatedAt = Date()
    private var activeKeepsHistory = true
    // A new attempt may fail while the previous result remains visible. Its
    // history policy belongs to that result, not the attempt's current settings.
    private var currentKeepsHistory = true
    private var finishedDuration: TimeInterval?
    private var isCancelling = false
    var isBusy: Bool { phase != .idle }
    var elapsedRecordingTime: TimeInterval {
        finishedDuration ?? max(0, Date().timeIntervalSince(startedAt ?? Date()))
    }

    init(store: DictationStore, speech: (any SpeechTranscribing)? = nil,
         intelligence: IntelligenceService? = nil,
         transformation: Transformation? = nil,
         preferences: UserDefaults = .standard, speechModels: ParakeetModelStore? = nil) {
        let models = speechModels ?? ParakeetModelStore()
        self.speechModels = models
        let resolvedSpeech = speech ?? SpeechProviderService(preferences: preferences, models: models)
        let resolvedIntelligence = intelligence ?? IntelligenceService()
        self.store = store
        self.speech = resolvedSpeech
        self.intelligence = resolvedIntelligence
        usesSystemWritingModel = transformation == nil
        self.transformation = transformation ?? { text, mode, instructions, vocabulary in
            try await resolvedIntelligence.transform(text, mode: mode, customInstructions: instructions, vocabulary: vocabulary)
        }
        resolvedSpeech.onInterruption = { [weak self] in
            guard let self else { return }
            if self.phase == .preparing {
                // Invalidate the pending start before it can display Listening.
                self.notice = "Recording was interrupted before it was ready. Try again."
                self.cancel()
            } else if self.phase == .recording {
                self.finish()
            }
        }
        store.onEntriesChanged = { [weak self] previous, updated in
            self?.reconcileCurrent(previous: previous, updated: updated)
        }
    }

    /// Prepare only model resources. Permission prompts and microphone activation
    /// still belong to the person's Record action.
    func prepareForRecording(locale: String, vocabulary: String) {
        if isInBackground { preparationSuppressedForMemoryPressure = false }
        isInBackground = false
        guard phase == .idle, !preparationSuppressedForMemoryPressure else { return }
        resourceReleaseTask?.cancel()
        resourceReleaseTask = nil
        releaseWhenIdle = false
        preparationTask?.cancel()
        let phrases = vocabulary.split(separator: "\n").map(String.init)
        preparationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.phase == .idle, !self.isInBackground else { return }
            // Passive readiness failures must not turn the quiet home screen into
            // an error. Record remains the authoritative, actionable retry.
            try? await self.speech.prewarm(localeIdentifier: locale, contextualStrings: phrases)
        }
    }

    func appDidReceiveMemoryWarning() {
        preparationTask?.cancel()
        preparationTask = nil
        releaseWhenIdle = true
        preparationSuppressedForMemoryPressure = true
        scheduleResourceRelease(immediately: true)
    }

    private func scheduleResourceRelease(immediately: Bool = false) {
        resourceReleaseTask?.cancel()
        guard phase == .idle else { return }
        resourceReleaseTask = Task { [weak self] in
            if !immediately {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
            guard let self, !Task.isCancelled, self.phase == .idle,
                  self.isInBackground || self.releaseWhenIdle else { return }
            self.releaseWhenIdle = false
            self.intelligence.releasePreparedResources()
            await self.speech.releasePreparedResources()
        }
    }

    func start(style: WritingStyle, locale: String, vocabulary: String, saveHistory: Bool) {
        guard phase == .idle else { return }
        resourceReleaseTask?.cancel()
        // Reset before yielding so a previous private result cannot become this
        // recording's background checkpoint. Keep the selected style as a value snapshot.
        speech.resetTranscript()
        activeStyle = style
        activeLocale = locale
        activeVocabulary = vocabulary.split(separator: "\n").map(String.init)
        activeKeepsHistory = saveHistory
        finishedDuration = nil
        isCancelling = false
        activeDictationID = UUID()
        phase = .preparing
        notice = nil
        resultNote = nil
        let token = UUID(); generation = token
        let phrases = activeVocabulary
        operation = Task {
            do {
                try Task.checkCancellation()
                try await speech.start(localeIdentifier: locale, contextualStrings: phrases)
                // Cancellation owns its own cleanup. A stale completion must never
                // cancel a subsequent service session or mutate the current screen.
                guard generation == token, !Task.isCancelled else { return }
                activeCreatedAt = Date()
                startedAt = activeCreatedAt
                current = nil
                phase = .recording
                if usesSystemWritingModel, !activeStyle.isOriginal { intelligence.prewarm() }
                operation = nil
                feedback(.medium)
            } catch {
                guard generation == token else { return }
                await speech.cancel()
                guard generation == token else { return }
                if !(error is CancellationError) { notice = error.localizedDescription }
                completeOperation(token: token)
            }
        }
    }

    func finish() {
        guard phase == .recording else { return }
        phase = .finishing
        let duration = elapsedRecordingTime
        finishedDuration = duration
        let token = generation
        feedback(.light)
        operation = Task {
            defer { completeOperation(token: token) }
            do {
                let raw = try await speech.stop()
                guard generation == token, !Task.isCancelled else { return }
                await accept(raw, duration: duration, token: token)
            } catch {
                guard generation == token else { return }
                recoverPartial(duration: duration,
                               note: "Recording ended early. The text captured so far is here.",
                               error: error)
            }
        }
    }

    func cancel() {
        guard isBusy else { return }
        let token = UUID(); generation = token
        operation?.cancel()
        isCancelling = true
        phase = .finishing
        endBackgroundFinalization()
        // Keep cancellation tracked and generation-scoped just like recording.
        // Repeated cancellation can share SpeechService's cleanup safely.
        operation = Task {
            await speech.cancel()
            completeOperation(token: token)
        }
    }

    func rework(style: WritingStyle, vocabulary: String) {
        guard phase == .idle, let original = current else { return }
        activeStyle = style
        activeVocabulary = vocabulary.split(separator: "\n").map(String.init)
        phase = .refining
        notice = nil
        resultNote = nil
        let token = UUID(); generation = token
        operation = Task {
            defer { completeOperation(token: token) }
            await refine(original, token: token)
        }
    }

    /// Reuse the latest saved version, even if new recordings are currently private.
    /// A stale History screen must not resurrect an entry that has been deleted.
    func reworkSaved(_ id: UUID, style: WritingStyle, vocabulary: String) {
        guard phase == .idle, let saved = store.entries.first(where: { $0.id == id }) else { return }
        current = saved
        currentKeepsHistory = true
        resetCopyFeedback()
        rework(style: style, vocabulary: vocabulary)
    }

    func updateText(_ text: String) {
        guard phase == .idle, var entry = current else { return }
        entry.text = text; current = entry
        resetCopyFeedback()
        if currentKeepsHistory { store.save(entry) }
    }

    func copy(_ text: String) {
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true])
        copied = true
        feedback(.light)
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }

    private func resetCopyFeedback() {
        copied = false
        copyFeedbackTask?.cancel()
    }

    func appDidEnterBackground() {
        isInBackground = true
        preparationTask?.cancel()
        preparationTask = nil
        switch phase {
        case .recording:
            checkpointPartial(duration: elapsedRecordingTime)
            beginBackgroundFinalization()
            finish()
        case .finishing:
            if !isCancelling {
                checkpointPartial(duration: elapsedRecordingTime)
                beginBackgroundFinalization()
            }
        case .preparing:
            cancel()
        case .refining:
            resultNote = "Writing paused when Sayso moved to the background. Your current text is unchanged, and the original is still available."
            cancel()
        case .idle:
            scheduleResourceRelease()
        }
    }

    private func completeOperation(token: UUID) {
        guard generation == token else { return }
        startedAt = nil
        phase = .idle
        operation = nil
        isCancelling = false
        if isInBackground || releaseWhenIdle { scheduleResourceRelease(immediately: releaseWhenIdle) }
        endBackgroundFinalization()
    }

    private func reconcileCurrent(previous: [Dictation], updated: [Dictation]) {
        // A history operation must not replace a private, unsaved result. Only
        // reconcile an entry that was actually part of the store before this edit.
        guard let entry = current, let previousSaved = previous.first(where: { $0.id == entry.id }) else { return }
        let saved = updated.first { $0.id == entry.id }
        // An unrelated history change must not roll back an in-memory edit whose
        // own save failed. Reconcile only when this stored entry actually changed.
        guard saved != previousSaved, saved != entry else { return }
        current = saved
        resultNote = nil
        resetCopyFeedback()
    }

    private func accept(_ raw: String, duration: TimeInterval, token: UUID) async {
        guard generation == token, !Task.isCancelled else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            notice = "No words were transcribed. Check that Sayso’s language matches the audio and try again."
            return
        }
        // Commit the source before any model request, including when writing is
        // unavailable or the app subsequently suspends.
        saveOriginal(text, duration: duration)
        guard let entry = current, !activeStyle.isOriginal else { return }
        guard backgroundTask == .invalid && UIApplication.shared.applicationState != .background else {
            resultNote = "Your transcript is here. Choose a writing mode to refine it."
            return
        }
        phase = .refining
        guard generation == token, !Task.isCancelled else { return }
        await refine(entry, token: token)
    }

    private func saveOriginal(_ raw: String, duration: TimeInterval) {
        // A background checkpoint and the eventual final text represent the
        // same recording, so completing it updates one saved entry.
        let entry = Dictation(id: activeDictationID, createdAt: activeCreatedAt,
                              text: raw, original: raw, mode: .transcript,
                              duration: duration, localeIdentifier: speech.usesAutomaticLanguageDetection ? "und" : activeLocale)
        current = entry
        resetCopyFeedback()
        currentKeepsHistory = activeKeepsHistory
        if currentKeepsHistory { store.save(entry) }
    }

    private func checkpointPartial(duration: TimeInterval) {
        let partial = speech.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty { saveOriginal(partial, duration: duration) }
    }

    private func recoverPartial(duration: TimeInterval, note: String, error: Error) {
        let partial = speech.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            saveOriginal(partial, duration: duration)
            resultNote = note
        } else if !(error is CancellationError) {
            notice = error.localizedDescription
        }
    }

    private func refine(_ entry: Dictation, token: UUID) async {
        guard generation == token, !Task.isCancelled else { return }
        let style = activeStyle
        do {
            // Rewriting should honor corrections made in Home or History. The
            // original remains archival; selecting Original explicitly restores it.
            let text: String
            if style.isOriginal {
                text = entry.original
            } else {
                text = try await transformation(entry.text, style.transformationMode, style.prompt, activeVocabulary)
            }
            guard generation == token, !Task.isCancelled else { return }
            var refined = entry
            refined.text = text; refined.mode = style.mode
            refined.writingStyle = style.isOriginal ? nil : style
            current = refined
            resetCopyFeedback()
            if currentKeepsHistory { store.save(refined) }
            feedback(.light)
        } catch {
            guard generation == token else { return }
            let retained = "Your current text is unchanged, and the original is still available."
            resultNote = error is CancellationError ? retained : retained + " " + error.localizedDescription
        }
    }

    /// Requests finite execution to drain stopped audio and retain the transcript.
    private func beginBackgroundFinalization() {
        guard backgroundTask == .invalid else { return }
        let token = generation
        backgroundGeneration = token
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish dictation") { [weak self] in
            self?.backgroundFinalizationExpired(token: token)
        }
    }

    private func backgroundFinalizationExpired(token: UUID) {
        guard generation == token, backgroundGeneration == token else { return }
        // Save synchronously while the expiration callback still has execution
        // time. The microphone was stopped at the start of finalization.
        let partial = speech.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            saveOriginal(partial, duration: elapsedRecordingTime)
            resultNote = "Recording stopped when Sayso moved to the background. The text captured so far is here."
        }
        cancel()
    }

    private func endBackgroundFinalization() {
        guard backgroundTask != .invalid else { backgroundGeneration = nil; return }
        let identifier = backgroundTask
        backgroundTask = .invalid
        backgroundGeneration = nil
        UIApplication.shared.endBackgroundTask(identifier)
    }

    private func feedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    #if DEBUG
    func loadPreviewResult() {
        current = Dictation(text: "Let’s keep it simple. A quiet space to collect your thoughts, and a little help finding the right words.", original: "um let's keep it simple a quiet space to collect your thoughts and a little help finding the right words", mode: .clean, duration: 14, localeIdentifier: "en-US")
    }
    #endif
}
