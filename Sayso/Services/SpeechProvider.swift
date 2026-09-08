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

    init(selection: @escaping () -> SpeechProvider, factory: @escaping Factory) {
        self.selection = selection
        self.factory = factory
    }

    convenience init(preferences: UserDefaults, models: ParakeetModelStore) {
        self.init(selection: {
            SpeechProvider.selected(in: preferences)
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
            await finish(service, token: token)
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

    func transcribeFile(at url: URL, localeIdentifier: String, contextualStrings: [String]) async throws -> String {
        let (service, token) = try begin()
        do {
            let text = try await service.transcribeFile(at: url, localeIdentifier: localeIdentifier, contextualStrings: contextualStrings)
            try check(token)
            await finish(service, token: token)
            return text
        } catch {
            await finish(service, token: token)
            throw error
        }
    }

    private func begin() throws -> (any SpeechTranscribing, UUID) {
        guard active == nil else { throw SpeechServiceError.busy }
        lastText = ""
        lastDiagnostics = nil
        sessionProvider = selection()
        let service = try factory(sessionProvider)
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

    private func finish(_ service: any SpeechTranscribing, token: UUID) async {
        guard generation == token else { return }
        let text = service.partialText
        let report = service.diagnosticsReport
        service.onInterruption = nil
        await service.cancel()
        guard generation == token else { return }
        lastText = text
        lastDiagnostics = report ?? service.diagnosticsReport
        active = nil
    }
}
