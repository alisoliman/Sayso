import Foundation
import Observation
import UIKit

@MainActor @Observable
final class DictationController {
    enum Phase: Equatable { case idle, preparing, recording, finishing, refining }
    enum Destination: Equatable { case app, keyboard }
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
    private(set) var destination = Destination.app
    @ObservationIgnored private let keyboardRecording: KeyboardRecordingCoordinator
    @ObservationIgnored private let transformation: Transformation
    @ObservationIgnored private let usesSystemWritingModel: Bool
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var resourceReleaseTask: Task<Void, Never>?
    @ObservationIgnored private let preferences: UserDefaults
    private var isInBackground = false
    private var releaseWhenIdle = false
    private var preparationSuppressedForMemoryPressure = false
    private var keyboardStyles: [WritingStyle] = []
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var backgroundGeneration: UUID?
    private var generation = UUID()
    private var activeMode = WritingMode.transcript
    private var activeTransformationMode = WritingMode.transcript
    private var activeWritingStyle: WritingStyle?
    private var activeLocale = "en-US"
    private var activeInstructions = ""
    private var activeVocabulary: [String] = []
    private var activeDictationID = UUID()
    private var activeCreatedAt = Date()
    private var activeKeepsHistory = true
    // A new attempt may fail while the previous result remains visible. Its
    // history policy belongs to that result, not the attempt's current settings.
    private var currentKeepsHistory = true
    private var finishedDuration: TimeInterval?
    private var isCancelling = false
    private var keyboardResultCommitted = false
    var isBusy: Bool { phase != .idle }
    var canCancel: Bool { isBusy && !keyboardResultCommitted }
    var elapsedRecordingTime: TimeInterval { recordingDuration }

    init(store: DictationStore, speech: (any SpeechTranscribing)? = nil,
         intelligence: IntelligenceService? = nil,
         transformation: Transformation? = nil, keyboardRecording: KeyboardRecordingCoordinator? = nil,
         preferences: UserDefaults = .standard, speechModels: ParakeetModelStore? = nil) {
        let models = speechModels ?? ParakeetModelStore()
        self.speechModels = models
        self.preferences = preferences
        let resolvedSpeech = speech ?? SpeechProviderService(preferences: preferences, models: models)
        let resolvedIntelligence = intelligence ?? IntelligenceService()
        self.store = store
        self.speech = resolvedSpeech
        self.intelligence = resolvedIntelligence
        self.keyboardRecording = keyboardRecording ?? KeyboardRecordingCoordinator()
        usesSystemWritingModel = transformation == nil
        self.transformation = transformation ?? { text, mode, instructions, vocabulary in
            try await resolvedIntelligence.transform(text, mode: mode, customInstructions: instructions, vocabulary: vocabulary)
        }
        resolvedSpeech.onInterruption = { [weak self] in
            guard let self else { return }
            if self.phase == .preparing {
                // Audio may already be active while ActivityKit finishes setup.
                // Invalidate that pending start before it can display Listening.
                self.notice = "Recording was interrupted before it was ready. Try again."
                self.cancel()
            } else if self.phase == .recording {
                self.finish()
            }
        }
        self.keyboardRecording.onStop = { [weak self] in
            guard let self else { return }
            if self.phase == .preparing { self.cancel() } else { self.finish() }
        }
        self.keyboardRecording.onSelectMode = { [weak self] id in
            guard let self, self.destination == .keyboard, self.phase == .recording,
                  let style = self.keyboardStyles.first(where: { $0.id == id }) else { return }
            self.configureWriting(mode: style.mode, instructions: style.prompt, writingStyle: style)
            // The keyboard can choose a writing mode after recording began in
            // Original. Give its model lead time while speech finishes.
            if self.usesSystemWritingModel, self.activeTransformationMode != .transcript { self.intelligence.prewarm() }
        }
        self.keyboardRecording.onCancel = { [weak self] in self?.cancel() }
        self.keyboardRecording.onExpiration = { [weak self] in self?.keyboardCompletionExpired() }
        self.keyboardRecording.onFailure = { [weak self] error in
            guard let self, self.destination == .keyboard, self.isBusy else { return }
            self.notice = error.localizedDescription
            if self.phase == .recording { self.finish() }
        }
        self.keyboardRecording.onCheckpoint = { [weak self] in
            guard let self, self.phase == .recording, UIApplication.shared.applicationState == .background else { return }
            self.checkpointPartial(duration: self.recordingDuration)
        }
        store.onEntriesChanged = { [weak self] previous, updated in
            self?.reconcileCurrent(previous: previous, updated: updated)
        }
    }

    /// Prepare only model resources. Permission prompts and microphone activation
    /// still belong to the person's Record action.
    func prepareForRecording(locale: String, vocabulary: String, mode: WritingMode = .transcript) {
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

    func start(mode: WritingMode, locale: String, instructions: String, vocabulary: String, saveHistory: Bool, destination: Destination = .app, writingStyle: WritingStyle? = nil) {
        guard phase == .idle else { return }
        resourceReleaseTask?.cancel()
        configure(mode: mode, locale: locale, instructions: instructions, vocabulary: vocabulary, saveHistory: saveHistory, writingStyle: writingStyle)
        self.destination = destination
        if destination == .keyboard {
            // Snapshot complete prompts in the app. Only display metadata crosses
            // into the keyboard, and a mid-recording library edit cannot change it.
            var catalog = WritingStyleStore(defaults: preferences).styles
            if let writingStyle {
                catalog.removeAll { $0.id == writingStyle.id }
                catalog.insert(writingStyle, at: 0)
            }
            keyboardStyles = Array(catalog.filter {
                ($0.isOriginal || !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
                $0.id.utf8.count <= 128
            }.prefix(24))
        }
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
                startedAt = Date()
                if destination == .keyboard {
                    let modes = keyboardStyles.map {
                        KeyboardRecordingSessionStore.Mode(id: $0.id, title: Self.keyboardTitle($0.title), symbol: $0.symbol)
                    }
                    let selectedID = activeWritingStyle?.id ?? activeMode.rawValue
                    try await keyboardRecording.start(sessionID: activeDictationID, availableModes: modes,
                        selectedModeID: modes.contains(where: { $0.id == selectedID }) ? selectedID : nil,
                        now: startedAt ?? Date())
                    guard generation == token, !Task.isCancelled else { return }
                }
                current = nil
                activeCreatedAt = startedAt ?? Date()
                phase = .recording
                if usesSystemWritingModel, activeMode != .transcript { intelligence.prewarm() }
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
        let duration = recordingDuration
        finishedDuration = duration
        let token = generation
        feedback(.light)
        if destination == .keyboard, UIApplication.shared.applicationState == .background { beginBackgroundFinalization() }
        operation = Task {
            defer { completeOperation(token: token) }
            do {
                // Begin stopping capture before awaiting a system UI update.
                async let stopped = speech.stop()
                if destination == .keyboard { await keyboardRecording.transition(to: .finishing) }
                let raw = try await stopped
                guard generation == token, !Task.isCancelled else { return }
                await accept(raw, duration: duration, token: token)
            } catch {
                guard generation == token else { return }
                recoverPartial(duration: duration,
                               note: "Recording ended early. The text captured so far is here.",
                               error: error)
            }
            await completeKeyboardRecording(token: token)
        }
    }

    func cancel(discardRecording: Bool = true, terminalPhase: RecordingActivityAttributes.Phase = .cancelled) {
        guard isBusy, !keyboardResultCommitted || !discardRecording else { return }
        let previousOperation = operation
        let keyboardID = destination == .keyboard ? keyboardRecording.sessionID : nil
        if let keyboardID { keyboardRecording.quiesce(sessionID: keyboardID) }
        if discardRecording, destination == .keyboard, current?.id == activeDictationID {
            if let saved = store.entries.first(where: { $0.id == activeDictationID }) { store.delete(saved.id) }
            current = nil
            resultNote = nil
        }
        let token = UUID(); generation = token
        previousOperation?.cancel()
        isCancelling = true
        phase = .finishing
        endBackgroundFinalization()
        // Keep cancellation tracked and generation-scoped just like recording.
        // Repeated cancellation can share SpeechService's cleanup safely.
        operation = Task {
            await speech.cancel()
            if let keyboardID { await keyboardRecording.end(sessionID: keyboardID, phase: terminalPhase, note: nil) }
            completeOperation(token: token)
        }
    }

    func rework(mode: WritingMode, instructions: String, vocabulary: String, writingStyle: WritingStyle? = nil) {
        guard phase == .idle, let original = current else { return }
        configureWriting(mode: mode, instructions: instructions, writingStyle: writingStyle)
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
    func reworkSaved(_ id: UUID, mode: WritingMode, instructions: String, vocabulary: String, writingStyle: WritingStyle? = nil) {
        guard phase == .idle, let saved = store.entries.first(where: { $0.id == id }) else { return }
        current = saved
        currentKeepsHistory = true
        copied = false
        rework(mode: mode, instructions: instructions, vocabulary: vocabulary, writingStyle: writingStyle)
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
        if keyboardResultCommitted {
            beginBackgroundFinalization()
            return
        }
        switch phase {
        case .recording:
            checkpointPartial(duration: recordingDuration)
            if destination == .keyboard { return }
            beginBackgroundFinalization()
            finish()
        case .finishing:
            if !isCancelling {
                checkpointPartial(duration: recordingDuration)
                beginBackgroundFinalization()
            }
        case .preparing:
            cancel()
        case .refining:
            if destination == .keyboard, keyboardRecording.sessionID != nil {
                beginBackgroundFinalization()
                return
            }
            resultNote = "Writing paused when Sayso moved to the background. Your current text is unchanged, and the original is still available."
            cancel()
        case .idle:
            scheduleResourceRelease()
        }
    }

    private var recordingDuration: TimeInterval {
        finishedDuration ?? max(0, Date().timeIntervalSince(startedAt ?? Date()))
    }

    private func configure(mode: WritingMode, locale: String, instructions: String, vocabulary: String, saveHistory: Bool, writingStyle: WritingStyle?) {
        // Reset synchronously before the task can yield to an app-background
        // callback. A previous transcript must never become a new recording's checkpoint.
        speech.resetTranscript()
        destination = .app
        configureWriting(mode: mode, instructions: instructions, writingStyle: writingStyle)
        activeLocale = locale
        activeVocabulary = vocabulary.split(separator: "\n").map(String.init)
        activeKeepsHistory = saveHistory
        finishedDuration = nil
        keyboardResultCommitted = false
        isCancelling = false
        activeDictationID = UUID()
        activeCreatedAt = Date()
    }

    private func configureWriting(mode: WritingMode, instructions: String, writingStyle: WritingStyle?) {
        // Copy the complete style before recording or rewriting can yield.
        // Changes to the mode library apply only to the next operation.
        activeWritingStyle = writingStyle
        activeMode = writingStyle?.mode ?? mode
        activeTransformationMode = writingStyle?.transformationMode ?? mode
        activeInstructions = writingStyle?.prompt ?? instructions
    }

    private static func keyboardTitle(_ title: String) -> String {
        guard title.utf8.count > 120 else { return title }
        var shortened = ""
        for character in title {
            guard shortened.utf8.count + String(character).utf8.count <= 117 else { break }
            shortened.append(character)
        }
        return shortened.isEmpty ? "Custom" : shortened + "…"
    }

    private func completeOperation(token: UUID) {
        guard generation == token else { return }
        startedAt = nil
        phase = .idle
        operation = nil
        isCancelling = false
        keyboardResultCommitted = false
        destination = .app
        keyboardStyles = []
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
        copied = false
        copyFeedbackTask?.cancel()
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
        guard let entry = current, activeMode != .transcript else { return }
        guard destination == .keyboard || (backgroundTask == .invalid && UIApplication.shared.applicationState != .background) else {
            resultNote = "Your transcript is here. Choose a writing mode to refine it."
            return
        }
        phase = .refining
        if destination == .keyboard { await keyboardRecording.transition(to: .refining) }
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
        let mode = activeMode
        let transformationMode = activeTransformationMode
        let writingStyle = activeWritingStyle
        let instructions = activeInstructions
        let vocabulary = activeVocabulary
        do {
            // Rewriting should honor corrections made in Home or History. The
            // original remains archival; selecting Original explicitly restores it.
            let text: String
            if mode == .transcript {
                text = entry.original
            } else {
                text = try await transformation(entry.text, transformationMode, instructions, vocabulary)
            }
            guard generation == token, !Task.isCancelled else { return }
            var refined = entry
            refined.text = text; refined.mode = mode
            refined.writingStyle = mode == .transcript ? nil : writingStyle
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

    private func completeKeyboardRecording(token: UUID) async {
        guard generation == token, destination == .keyboard, let id = keyboardRecording.sessionID else { return }
        var completed = false
        if let entry = current, entry.id == id {
            do {
                guard try keyboardRecording.publish(entry) else {
                    // A Discard accepted before the atomic completion boundary
                    // wins even when it arrived after the most recent poll.
                    cancel()
                    return
                }
                keyboardResultCommitted = true
                completed = true
                let ready = "Ready in the Sayso keyboard. If it hasn’t appeared in your text field, tap Insert."
                resultNote = resultNote.map { $0 + " " + ready } ?? ready
            } catch {
                // Publication is already final if only metadata cleanup failed.
                // A late Cancel must not hide a result that is ready to insert.
                completed = keyboardRecording.publicationCommitted
                keyboardResultCommitted = completed
                notice = error.localizedDescription
            }
        }
        await keyboardRecording.end(sessionID: id, phase: completed ? .ready : .failed,
                                    note: completed ? nil : "Open Sayso to review your recording.")
    }

    /// Both the system background deadline and the independent completion limit
    /// retain the source before cancelling model work. No partial rewrite is sent.
    func keyboardCompletionExpired() {
        guard destination == .keyboard, isBusy, !isCancelling, !keyboardResultCommitted, keyboardRecording.sessionID != nil else { return }
        if phase != .refining || current?.id != activeDictationID { checkpointPartial(duration: recordingDuration) }
        var published = false
        if let entry = current, entry.id == activeDictationID {
            do {
                guard try keyboardRecording.publish(entry) else { cancel(); return }
                published = true
                keyboardResultCommitted = true
            } catch {
                published = keyboardRecording.publicationCommitted
                keyboardResultCommitted = published
                notice = error.localizedDescription
            }
            resultNote = "Your transcript is ready. You can refine it in Sayso later."
        }
        cancel(discardRecording: false, terminalPhase: published ? .ready : .failed)
    }

    /// Requests finite execution to drain stopped audio and finish writing. The
    /// audio background mode applies only to an explicit ongoing keyboard session.
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
        if keyboardResultCommitted { completeOperation(token: token); return }
        if destination == .keyboard { keyboardCompletionExpired(); return }
        // Save synchronously while the expiration callback still has execution
        // time. The microphone was stopped at the start of finalization.
        let partial = speech.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            saveOriginal(partial, duration: recordingDuration)
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
