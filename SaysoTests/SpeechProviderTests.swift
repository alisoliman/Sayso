import Foundation
import XCTest
@testable import Sayso

@MainActor
final class SpeechProviderTests: XCTestCase {
    func testPassivePreparationAndRepeatedRecordingsReuseOneBackendUntilReleased() async throws {
        var factories = 0
        var backends: [ProviderTestSpeech] = []
        let service = SpeechProviderService(selection: { .parakeet }, factory: { _ in
            factories += 1
            let backend = ProviderTestSpeech()
            backend.stopResult = "A finished recording"
            backends.append(backend)
            return backend
        })
        try await service.prewarm(localeIdentifier: "en-US", contextualStrings: ["Sayso"])
        XCTAssertEqual(factories, 1)
        XCTAssertEqual(backends[0].warmups, [.init(locale: "en-US", vocabulary: ["Sayso"])])
        XCTAssertTrue(backends[0].starts.isEmpty)
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.status, "Ready")
        for _ in 0..<2 {
            try await service.start(localeIdentifier: "en-US", contextualStrings: [])
            _ = try await service.stop()
        }
        XCTAssertEqual(factories, 1, "Finishing a recording must preserve the loaded speech backend.")
        XCTAssertEqual(backends[0].starts.count, 2)
        await service.releasePreparedResources()
        XCTAssertEqual(backends[0].releaseCalls, 1)
        XCTAssertEqual(service.partialText, "A finished recording", "Reclaiming models must preserve the user's result.")
        try await service.prewarm(localeIdentifier: "en-US", contextualStrings: [])
        XCTAssertEqual(factories, 2)
    }

    func testWarmModelIdentityChangeReplacesBackendBeforeNextRecording() async throws {
        var identity = "installed-model-a"
        var backends: [ProviderTestSpeech] = []
        let service = SpeechProviderService(selection: { .parakeet }, cacheIdentity: { _ in identity }, factory: { _ in
            let backend = ProviderTestSpeech()
            backends.append(backend)
            return backend
        })
        try await service.prewarm(localeIdentifier: "en-US", contextualStrings: [])
        identity = "installed-model-b"
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        XCTAssertEqual(backends.count, 2)
        XCTAssertTrue(backends[0].starts.isEmpty, "A removed or replaced model must not be used from memory.")
        XCTAssertEqual(backends[1].starts.count, 1)
        await service.cancel()
    }

    func testIdleResourceReleaseCannotInterruptActiveRecording() async throws {
        let backend = ProviderTestSpeech()
        let service = SpeechProviderService(selection: { .apple }, factory: { _ in backend })
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        await service.releasePreparedResources()
        try await service.prewarm(localeIdentifier: "nl-NL", contextualStrings: [])
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(backend.releaseCalls, 0)
        XCTAssertTrue(backend.warmups.isEmpty)
        await service.cancel()
    }

    func testRecordingPinsProviderAndPreservesResultAfterBackendCleanup() async throws {
        var selected = SpeechProvider.parakeet
        let local = ProviderTestSpeech()
        let apple = ProviderTestSpeech()
        var requested: [SpeechProvider] = []
        let service = SpeechProviderService(selection: { selected }, factory: { provider in
            requested.append(provider)
            return provider == .parakeet ? local : apple
        })

        try await service.start(localeIdentifier: "nl-NL", contextualStrings: ["Sayso", "Amsterdam"])
        XCTAssertEqual(local.starts, [.init(locale: "nl-NL", vocabulary: ["Sayso", "Amsterdam"])])
        local.partialText = "Goedemorgen."
        local.level = 0.6
        local.status = "Listening locally"
        local.diagnosticsReport = "Local capture diagnostic"
        XCTAssertEqual(service.partialText, "Goedemorgen.")
        XCTAssertEqual(service.level, 0.6)
        XCTAssertEqual(service.status, "Listening locally")
        XCTAssertTrue(service.isRecording)
        service.resetTranscript()
        XCTAssertEqual(service.partialText, "Goedemorgen.", "Reset must not discard a running recording.")

        selected = .apple
        local.stopResult = "Goedemorgen Amsterdam."
        let result = try await service.stop()
        XCTAssertEqual(result, "Goedemorgen Amsterdam.")
        XCTAssertEqual(requested, [.parakeet], "Changing settings must not replace an active backend.")
        XCTAssertEqual(local.stopCalls, 1)
        XCTAssertEqual(apple.stopCalls, 0)
        XCTAssertEqual(local.partialText, "", "The stub deliberately clears transient state during cleanup.")
        XCTAssertEqual(service.partialText, result)
        XCTAssertTrue(service.usesAutomaticLanguageDetection)
        XCTAssertEqual(service.diagnosticsReport, "Local capture diagnostic")
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.level, 0)

        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        XCTAssertEqual(requested, [.parakeet, .apple])
        XCTAssertFalse(service.usesAutomaticLanguageDetection)
        XCTAssertEqual(service.partialText, "")
        XCTAssertNil(service.diagnosticsReport)
        await service.cancel()
        service.resetTranscript()
        XCTAssertEqual(service.partialText, "")
    }

    func testFactoryFailureDoesNotFallBackAndLeavesRouterReusable() async throws {
        var selected = SpeechProvider.parakeet
        let apple = ProviderTestSpeech()
        var requested: [SpeechProvider] = []
        let service = SpeechProviderService(selection: { selected }, factory: { provider in
            requested.append(provider)
            if provider == .parakeet { throw ProviderTestError.unavailable }
            return apple
        })

        do {
            try await service.start(localeIdentifier: "en-US", contextualStrings: [])
            XCTFail("The selected local backend is unavailable.")
        } catch { XCTAssertTrue(error is ProviderTestError) }
        XCTAssertEqual(requested, [.parakeet])
        XCTAssertTrue(apple.starts.isEmpty)
        XCTAssertFalse(service.isRecording)

        selected = .apple
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        XCTAssertTrue(service.isRecording)
        await service.cancel()
    }

    func testProviderPreferenceDefaultsToAppleAndRespectsExplicitLocalSelection() async throws {
        let suiteName = "SpeechProviderTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let backend = ProviderTestSpeech()
        var requested: [SpeechProvider] = []
        let service = SpeechProviderService(selection: { SpeechProvider.selected(in: preferences) }, factory: { provider in
            requested.append(provider)
            return backend
        })

        XCTAssertEqual(SpeechProvider.defaultProvider, .apple)
        XCTAssertEqual(SpeechProvider.selected(in: preferences), .apple)
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        await service.cancel()

        preferences.set("removed-provider", forKey: SpeechProvider.preferenceKey)
        XCTAssertEqual(SpeechProvider.selected(in: preferences), .apple)
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        await service.cancel()

        preferences.set(SpeechProvider.parakeet.rawValue, forKey: SpeechProvider.preferenceKey)
        XCTAssertEqual(SpeechProvider.selected(in: preferences), .parakeet)
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        await service.cancel()
        XCTAssertEqual(requested, [.apple, .apple, .parakeet])
    }

    func testExplicitParakeetSelectionRequiresLocalModelWithoutStartingDownload() async throws {
        let root = temporaryRoot()
        let suiteName = "SpeechProviderTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            preferences.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(SpeechProvider.parakeet.rawValue, forKey: SpeechProvider.preferenceKey)
        let modelStore = ParakeetModelStore(root: root)
        let service = SpeechProviderService(preferences: preferences, models: modelStore)
        XCTAssertFalse(modelStore.isInstalled)

        do {
            try await service.start(localeIdentifier: "en-US", contextualStrings: [])
            XCTFail("Selecting Parakeet must require an explicitly installed local model.")
        } catch {
            guard case ParakeetModelStore.ModelError.notInstalled = error else {
                return XCTFail("Missing Parakeet must fail before invoking Apple Speech: \(error)")
            }
        }
        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(modelStore.isWorking, "Recording must not start a model download.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelStore.directory.path))
    }

    func testBusySessionRejectsRecordingWithoutAnotherFactoryCall() async throws {
        let backend = ProviderTestSpeech()
        var factories = 0
        let service = SpeechProviderService(selection: { .parakeet }, factory: { _ in
            factories += 1
            return backend
        })
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        do {
            try await service.start(localeIdentifier: "nl-NL", contextualStrings: [])
            XCTFail("A second recording must not take over the microphone.")
        } catch {
            guard case SpeechServiceError.busy = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(factories, 1)
        XCTAssertTrue(service.isRecording)
        await service.cancel()
    }

    func testInterruptionFromRetiredBackendCannotInterruptIdleOrNewSession() async throws {
        let old = ProviderTestSpeech()
        let next = ProviderTestSpeech()
        var factories = 0
        let service = SpeechProviderService(selection: { .parakeet }, factory: { _ in
            factories += 1
            return factories == 1 ? old : next
        })
        var interruptions = 0
        service.onInterruption = { interruptions += 1 }
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        let delayedInterruption = old.onInterruption
        delayedInterruption?()
        XCTAssertEqual(interruptions, 1)
        _ = try await service.stop()
        delayedInterruption?()
        XCTAssertEqual(interruptions, 1, "An already queued callback must not interrupt an idle router.")

        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        delayedInterruption?()
        XCTAssertEqual(interruptions, 1)
        XCTAssertEqual(factories, 1, "A successful stop keeps the backend warm.")
        old.onInterruption?()
        XCTAssertEqual(interruptions, 2)
        await service.cancel()
    }

    func testCancelledPreparationCannotCompleteOverNewSession() async throws {
        let gate = ProviderTestGate()
        let old = ProviderTestSpeech()
        old.startOverride = { await gate.wait() }
        let next = ProviderTestSpeech()
        var factories = 0
        let service = SpeechProviderService(selection: { .parakeet }, factory: { _ in
            factories += 1
            return factories == 1 ? old : next
        })
        let preparation = Task { try await service.start(localeIdentifier: "en-US", contextualStrings: []) }
        defer { gate.resume() }
        await waitUntil("First provider should be preparing") { gate.isWaiting }
        await service.cancel()
        try await service.start(localeIdentifier: "nl-NL", contextualStrings: [])
        next.partialText = "New live words"
        gate.resume()
        do {
            try await preparation.value
            XCTFail("The cancelled preparation must not report success.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(service.partialText, "New live words")
        XCTAssertEqual(next.cancelCalls, 0)
        await service.cancel()
    }

    func testCancelledStopCannotOverwriteAReplacementRecording() async throws {
        let gate = ProviderTestGate()
        let old = ProviderTestSpeech()
        old.stopOverride = {
            await gate.wait()
            return "Late final transcript"
        }
        let next = ProviderTestSpeech()
        var factories = 0
        let service = SpeechProviderService(selection: { .parakeet }, factory: { _ in
            factories += 1
            return factories == 1 ? old : next
        })
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        let stopping = Task { try await service.stop() }
        defer { gate.resume() }
        await waitUntil("Old recording should be finalizing") { gate.isWaiting }
        await service.cancel()
        try await service.start(localeIdentifier: "nl-NL", contextualStrings: [])
        next.partialText = "Replacement recording"
        gate.resume()
        do {
            _ = try await stopping.value
            XCTFail("An abandoned finalization must reject its late transcript.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(service.partialText, "Replacement recording")
        XCTAssertEqual(next.cancelCalls, 0)
        await service.cancel()
    }

    func testOlderCancellationCompletionCannotDiscardNewRecording() async throws {
        let firstGate = ProviderTestGate()
        let secondGate = ProviderTestGate()
        let old = ProviderTestSpeech()
        var cancellations = 0
        old.cancelOverride = {
            cancellations += 1
            if cancellations == 1 { await firstGate.wait() }
            else if cancellations == 2 { await secondGate.wait() }
        }
        let next = ProviderTestSpeech()
        var factories = 0
        let service = SpeechProviderService(selection: { .parakeet }, factory: { _ in
            factories += 1
            return factories == 1 ? old : next
        })
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        let firstCancellation = Task { await service.cancel() }
        defer { firstGate.resume(); secondGate.resume() }
        await waitUntil("First cancellation should suspend") { firstGate.isWaiting }
        let secondCancellation = Task { await service.cancel() }
        await waitUntil("Second cancellation should suspend") { secondGate.isWaiting }
        secondGate.resume()
        await secondCancellation.value
        try await service.start(localeIdentifier: "nl-NL", contextualStrings: [])
        next.partialText = "Current recording"
        firstGate.resume()
        await firstCancellation.value
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(service.partialText, "Current recording")
        XCTAssertEqual(next.cancelCalls, 0)
        await service.cancel()
    }

    func testFailedStopRetainsRecoverableTextAndDiagnosticAfterCleanup() async throws {
        let backend = ProviderTestSpeech()
        backend.stopOverride = {
            backend.partialText = "Words recovered before failure."
            backend.diagnosticsReport = "Capture ended early"
            throw ProviderTestError.interrupted
        }
        let service = SpeechProviderService(selection: { .parakeet }, factory: { _ in backend })
        try await service.start(localeIdentifier: "en-US", contextualStrings: [])
        do {
            _ = try await service.stop()
            XCTFail("The failure must reach the controller.")
        } catch { XCTAssertTrue(error is ProviderTestError) }
        XCTAssertEqual(service.partialText, "Words recovered before failure.")
        XCTAssertEqual(service.diagnosticsReport, "Capture ended early")
        XCTAssertEqual(backend.cancelCalls, 1)
        XCTAssertEqual(backend.partialText, "")
        service.resetTranscript()
        XCTAssertEqual(service.partialText, "")
    }

    func testCommitReplacesCompleteModelAndRemovesStagingAndPreviousCopy() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ParakeetModelStore(root: root)
        try makeModelFixture(at: store.directory, marker: "previous")
        let staging = root.appending(path: ".staging-test")
        try makeModelFixture(at: staging, marker: "replacement")
        store.refresh()
        XCTAssertTrue(store.isInstalled)

        try ParakeetModelStore.commit(staging: staging, destination: store.directory)
        store.refresh()
        XCTAssertTrue(store.isInstalled)
        XCTAssertEqual(try String(contentsOf: store.directory.appending(path: "fixture-marker"), encoding: .utf8), "replacement")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["parakeet-tdt-v3"])
    }

    func testIncompleteReplacementCannotDestroyExistingModel() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ParakeetModelStore(root: root)
        try makeModelFixture(at: store.directory, marker: "working")
        let staging = root.appending(path: ".staging-incomplete")
        try makeModelFixture(at: staging, marker: "broken")
        try FileManager.default.removeItem(at: staging.appending(path: "Encoder.mlmodelc/weights/weight.bin"))

        XCTAssertThrowsError(try ParakeetModelStore.commit(staging: staging, destination: store.directory))
        store.refresh()
        XCTAssertTrue(store.isInstalled)
        XCTAssertEqual(try String(contentsOf: store.directory.appending(path: "fixture-marker"), encoding: .utf8), "working")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".previous-") })
    }

    func testCancelledCommitPreservesWorkingModelAndCompleteStaging() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ParakeetModelStore(root: root)
        try makeModelFixture(at: store.directory, marker: "working")
        let staging = root.appending(path: ".staging-cancelled")
        try makeModelFixture(at: staging, marker: "replacement")
        // The child cannot begin on the main actor until this test yields below.
        let commit = Task { try ParakeetModelStore.commit(staging: staging, destination: store.directory) }
        commit.cancel()
        do {
            try await commit.value
            XCTFail("A cancelled installation must stop before replacing the working model.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try String(contentsOf: store.directory.appending(path: "fixture-marker"), encoding: .utf8), "working")
        XCTAssertNoThrow(try ParakeetModelFiles.validate(at: staging))
    }

    func testModelStoreRecognizesAndRemovesExplicitInstallation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ParakeetModelStore(root: root)
        let staging = root.appending(path: ".staging-first")
        try makeModelFixture(at: staging, marker: "first")
        try ParakeetModelStore.commit(staging: staging, destination: store.directory)
        store.refresh()
        XCTAssertTrue(store.isInstalled)
        store.remove()
        XCTAssertFalse(store.isInstalled)
        XCTAssertNil(store.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testRejectedImportPreservesExistingModelAndClearsWorkingState() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let installedRoot = root.appending(path: "installed")
        let store = ParakeetModelStore(root: installedRoot)
        try makeModelFixture(at: store.directory, marker: "working")
        store.refresh()
        let source = root.appending(path: "incomplete-source")
        try makeModelFixture(at: source, marker: "invalid-replacement")
        try FileManager.default.removeItem(at: source.appending(path: "Decoder.mlmodelc/model.mil"))

        store.importFolder(source)
        XCTAssertTrue(store.isWorking)
        await waitUntil("Invalid import should finish") { !store.isWorking }

        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.isInstalled)
        XCTAssertEqual(try String(contentsOf: store.directory.appending(path: "fixture-marker"), encoding: .utf8), "working")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installedRoot.path), ["parakeet-tdt-v3"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "An invalid import must not delete the user's source.")
    }

    func testImportedModelRemainsAvailableAfterSourceFolderIsRemoved() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let installedRoot = root.appending(path: "installed")
        let store = ParakeetModelStore(root: installedRoot)
        let source = root.appending(path: "source")
        try makeModelFixture(at: source, marker: "imported")

        store.importFolder(source)
        XCTAssertTrue(store.isWorking)
        await waitUntil("Valid import should finish") { !store.isWorking }
        XCTAssertNil(store.error)
        XCTAssertTrue(store.isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Import must copy the user's source.")
        try FileManager.default.removeItem(at: source)
        store.refresh()

        XCTAssertTrue(store.isInstalled, "Recognition must use an owned local copy independent of its import source.")
        XCTAssertEqual(try String(contentsOf: store.directory.appending(path: "fixture-marker"), encoding: .utf8), "imported")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installedRoot.path), ["parakeet-tdt-v3"])
    }

    func testRepositoryCheckoutWithLFSWeightsIsNotAnInstalledModel() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ParakeetModelStore(root: root)
        try makeModelFixture(at: store.directory, marker: "checkout")
        let pointer = "version https://git-lfs.github.com/spec/v1\noid sha256:placeholder\nsize 100000000\n"
        try Data(pointer.utf8).write(to: store.directory.appending(path: "Encoder.mlmodelc/weights/weight.bin"))

        XCTAssertThrowsError(try ParakeetModelFiles.validate(at: store.directory))
        store.refresh()
        XCTAssertFalse(store.isInstalled, "Git LFS metadata is not a usable downloaded model.")
    }

    func testVocabularyMustHaveEveryExpectedTokenID() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModelFixture(at: root, marker: "wrong-vocabulary")
        // The count matches v3, but the vocabulary is shifted by one token ID.
        let vocabulary = Dictionary(uniqueKeysWithValues: (1...8_192).map { (String($0), "token-\($0)") })
        try JSONSerialization.data(withJSONObject: vocabulary).write(to: root.appending(path: "parakeet_vocab.json"))

        XCTAssertThrowsError(try ParakeetModelFiles.validate(at: root)) { error in
            guard case ParakeetRuntimeError.invalidVocabulary = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testModelCannotDependOnWeightsOutsideItsInstalledFolder() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appending(path: "model")
        try makeModelFixture(at: model, marker: "linked-weights")
        let weights = model.appending(path: "Encoder.mlmodelc/weights")
        let external = root.appending(path: "external-weights")
        try FileManager.default.moveItem(at: weights, to: external)
        try FileManager.default.createSymbolicLink(at: weights, withDestinationURL: external)

        XCTAssertThrowsError(try ParakeetModelFiles.validate(at: model), "A copied model must remain complete when its import source is removed.")
    }

    private func temporaryRoot() -> URL {
        URL.temporaryDirectory.appending(path: "SpeechProviderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeModelFixture(at directory: URL, marker: String) throws {
        // Exercise file-level installation validation without loading synthetic bytes into Core ML.
        for bundle in ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc"] {
            let url = directory.appending(path: bundle)
            try FileManager.default.createDirectory(at: url.appending(path: "weights"), withIntermediateDirectories: true)
            for payload in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                try Data("fixture payload".utf8).write(to: url.appending(path: payload))
            }
        }
        let vocabulary = Dictionary(uniqueKeysWithValues: (0..<8_192).map { (String($0), "token-\($0)") })
        try JSONSerialization.data(withJSONObject: vocabulary).write(to: directory.appending(path: "parakeet_vocab.json"))
        try Data(marker.utf8).write(to: directory.appending(path: "fixture-marker"))
    }

    private func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async {
        // Simulator file coordination can take several seconds under load.
        // Await the actual working-state transition before removing fixtures.
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(description, file: file, line: line)
    }
}

@MainActor
private final class ProviderTestSpeech: SpeechTranscribing {
    struct Request: Equatable {
        let locale: String
        let vocabulary: [String]
    }
    var partialText = ""
    var level = 0.0
    var status = "Ready"
    var isRecording = false
    var diagnosticsReport: String?
    var onInterruption: (() -> Void)?
    var starts: [Request] = []
    var warmups: [Request] = []
    var releaseCalls = 0
    var stopCalls = 0
    var cancelCalls = 0
    var stopResult = ""
    var startOverride: (() async throws -> Void)?
    var stopOverride: (() async throws -> String)?
    var cancelOverride: (() async -> Void)?

    func resetTranscript() { partialText = "" }
    func prewarm(localeIdentifier: String, contextualStrings: [String]) async throws {
        warmups.append(.init(locale: localeIdentifier, vocabulary: contextualStrings))
    }
    func releasePreparedResources() async { releaseCalls += 1 }
    func start(localeIdentifier: String, contextualStrings: [String]) async throws {
        starts.append(.init(locale: localeIdentifier, vocabulary: contextualStrings))
        try await startOverride?()
        isRecording = true
    }
    func stop() async throws -> String {
        stopCalls += 1
        partialText = try await stopOverride?() ?? stopResult
        isRecording = false
        return partialText
    }
    func cancel() async {
        cancelCalls += 1
        isRecording = false
        partialText = ""
        diagnosticsReport = nil
        level = 0
        await cancelOverride?()
    }
}

@MainActor
private final class ProviderTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func resume() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

private enum ProviderTestError: Error { case unavailable, interrupted }
