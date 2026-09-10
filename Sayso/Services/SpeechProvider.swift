import Foundation
import Observation

nonisolated enum SpeechProvider: String, CaseIterable, Identifiable {
    case apple
    case parakeet

    static let preferenceKey = "speechProvider"
    static let defaultProvider = SpeechProvider.apple
    static func selected(in preferences: UserDefaults) -> SpeechProvider {
        SpeechProvider(rawValue: preferences.string(forKey: preferenceKey) ?? "") ?? defaultProvider
    }
    var id: String { rawValue }
    var name: String { self == .parakeet ? "Parakeet · local" : "Apple Speech" }

    // Parakeet v3 detects its language automatically. The language preference is
    // only passed to Apple Speech; unsupported languages are not silently routed.
    var languageDescription: String {
        self == .parakeet
            ? "Parakeet detects 25 European languages automatically, including English and Dutch. Arabic, Chinese, Japanese and Korean are not supported."
            : "Choose the language you’ll speak."
    }
}

/// Selects one backend at the start of each operation. Preference changes never
/// switch a running session, and a missing model never falls back to Apple.
@MainActor @Observable
final class SpeechProviderService: SpeechTranscribing {
    typealias Factory = @MainActor (SpeechProvider) throws -> any SpeechTranscribing
    @ObservationIgnored private let selection: () -> SpeechProvider
    @ObservationIgnored private let factory: Factory
    @ObservationIgnored private let cacheIdentity: (SpeechProvider) throws -> String
    @ObservationIgnored private var cached: (provider: SpeechProvider, identity: String, service: any SpeechTranscribing)?
    private var active: (any SpeechTranscribing)?
    private var lastText = ""
    private var lastDiagnostics: String?
    private var generation = UUID()
    private var sessionProvider = SpeechProvider.apple
    var onInterruption: (() -> Void)?

    var partialText: String { active?.partialText ?? lastText }
    var level: Double { active?.level ?? 0 }
    var status: String { active?.status ?? "Ready" }
    var isRecording: Bool { active?.isRecording ?? false }
    var diagnosticsReport: String? { active?.diagnosticsReport ?? lastDiagnostics }
    var usesAutomaticLanguageDetection: Bool { sessionProvider == .parakeet }

    init(selection: @escaping () -> SpeechProvider,
         cacheIdentity: @escaping (SpeechProvider) throws -> String = { _ in "" },
         factory: @escaping Factory) {
        self.selection = selection
        self.factory = factory
        self.cacheIdentity = cacheIdentity
    }

    convenience init(preferences: UserDefaults, models: ParakeetModelStore) {
        self.init(selection: {
            SpeechProvider.selected(in: preferences)
        }, cacheIdentity: { provider in
            guard provider == .parakeet else { return "apple" }
            guard !models.isWorking else { throw ParakeetModelStore.ModelError.installInProgress }
            guard models.isInstalled else { throw ParakeetModelStore.ModelError.notInstalled }
            try ParakeetModelFiles.validate(at: models.directory)
            return models.installationRevision.uuidString
        }, factory: { provider in
            switch provider {
            case .apple: return SpeechService()
            case .parakeet:
                guard !models.isWorking else { throw ParakeetModelStore.ModelError.installInProgress }
                guard models.isInstalled else { throw ParakeetModelStore.ModelError.notInstalled }
                try ParakeetModelFiles.validate(at: models.directory)
                return ParakeetSpeechService(runtime: ParakeetRuntime(directory: models.directory))
            }
        })
    }

    func prewarm(localeIdentifier: String, contextualStrings: [String]) async throws {
        guard active == nil else { return }
        let service = try reusableService(for: selection())
        try await service.prewarm(localeIdentifier: localeIdentifier, contextualStrings: contextualStrings)
        try Task.checkCancellation()
    }

    func releasePreparedResources() async {
        guard active == nil else { return }
        let previous = cached
        cached = nil
        await previous?.service.releasePreparedResources()
    }

    func resetTranscript() {
        guard active == nil else { return }
        lastText = ""
    }

    func start(localeIdentifier: String, contextualStrings: [String]) async throws {
        let (service, token) = try begin()
        do {
            try await service.start(localeIdentifier: localeIdentifier, contextualStrings: contextualStrings)
            try check(token)
        } catch {
            await finish(service, token: token)
            throw error
        }
    }

    func stop() async throws -> String {
        guard let service = active else { throw SpeechServiceError.notRecording }
        let token = generation
        do {
            let text = try await service.stop()
            try check(token)
            await finish(service, token: token, retain: true)
            return text
        } catch {
            await finish(service, token: token)
            throw error
        }
    }

    func cancel() async {
        guard let service = active else { return }
        generation = UUID()
        let token = generation
        await finish(service, token: token)
    }

    private func begin() throws -> (any SpeechTranscribing, UUID) {
        guard active == nil else { throw SpeechServiceError.busy }
        lastText = ""
        lastDiagnostics = nil
        sessionProvider = selection()
        let service = try reusableService(for: sessionProvider)
        let token = UUID()
        generation = token
        active = service
        service.onInterruption = { [weak self] in
            guard self?.generation == token, self?.active != nil else { return }
            self?.onInterruption?()
        }
        return (service, token)
    }

    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
    }

    private func finish(_ service: any SpeechTranscribing, token: UUID, retain: Bool = false) async {
        guard generation == token else { return }
        if !retain, cached?.service === service { cached = nil }
        let text = service.partialText
        let report = service.diagnosticsReport
        service.onInterruption = nil
        await service.cancel()
        guard generation == token else { return }
        lastText = text
        lastDiagnostics = report ?? service.diagnosticsReport
        active = nil
        if !retain { await service.releasePreparedResources() }
    }

    private func reusableService(for provider: SpeechProvider) throws -> any SpeechTranscribing {
        let identity: String
        do { identity = try cacheIdentity(provider) }
        catch {
            retireCachedService()
            throw error
        }
        if let cached, cached.provider == provider, cached.identity == identity { return cached.service }
        retireCachedService()
        let service = try factory(provider)
        cached = (provider, identity, service)
        return service
    }

    private func retireCachedService() {
        let previous = cached
        cached = nil
        if let previous { Task { await previous.service.releasePreparedResources() } }
    }
}
