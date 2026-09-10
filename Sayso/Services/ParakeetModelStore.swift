import Foundation
import Observation

/// Installs a single known Parakeet variant in Application Support. Downloads
/// happen only in response to the model controls, never when recording starts.
@MainActor @Observable
final class ParakeetModelStore {
    let directory: URL
    private(set) var isInstalled = false
    private(set) var installationRevision = UUID()
    private(set) var isWorking = false
    private(set) var status = "Model not installed"
    var error: String?
    @ObservationIgnored private var operation: Task<Void, Never>?

    init(root: URL? = nil) {
        let root = root ?? URL.applicationSupportDirectory.appending(path: "Sayso/Models", directoryHint: .isDirectory)
        directory = root.appending(path: "parakeet-tdt-v3", directoryHint: .isDirectory)
        refresh()
    }

    func refresh() {
        guard !isWorking else { return }
        isInstalled = (try? ParakeetModelFiles.validate(at: directory)) != nil
        status = isInstalled ? "Installed on this iPhone" : "Model not installed"
    }

    func download() {
        install(status: "Installing Parakeet…") { staging in
            try await ParakeetModelFiles.download(to: staging)
        }
    }

    func importFolder(_ source: URL) {
        install(status: "Importing Parakeet…") { staging in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try ParakeetModelFiles.validate(at: source)
            try FileManager.default.copyItem(at: source, to: staging)
        }
    }

    func cancel() { operation?.cancel() }

    func remove() {
        guard !isWorking else { return }
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            installationRevision = UUID()
            error = nil
        } catch { self.error = error.localizedDescription }
        refresh()
    }

    private func install(status: String, populate: @escaping @Sendable (URL) async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        self.status = status
        error = nil
        let destination = directory
        operation = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let root = destination.deletingLastPathComponent()
                try Self.prepareRoot(root)
                let staging = root.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
                defer { try? FileManager.default.removeItem(at: staging) }
                try Task.checkCancellation()
                try await populate(staging)
                try Task.checkCancellation()
                try ParakeetModelFiles.validate(at: staging)
                try Self.commit(staging: staging, destination: destination)
            }
            do {
                try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                installationRevision = UUID()
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            isWorking = false
            operation = nil
            refresh()
        }
    }

    nonisolated static func prepareRoot(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    /// Rename on the same volume and restore the previous install on failure.
    /// All validation/cancellation checks happen before moving a working model.
    nonisolated static func commit(staging: URL, destination: URL) throws {
        try ParakeetModelFiles.validate(at: staging)
        try Task.checkCancellation()
        let files = FileManager.default
        let backup = destination.deletingLastPathComponent().appending(path: ".previous-\(UUID().uuidString)")
        let existed = files.fileExists(atPath: destination.path)
        if existed { try files.moveItem(at: destination, to: backup) }
        do {
            try files.moveItem(at: staging, to: destination)
        } catch {
            if existed { try? files.moveItem(at: backup, to: destination) }
            throw error
        }
        if existed { try? files.removeItem(at: backup) }
    }

    nonisolated enum ModelError: LocalizedError {
        case installInProgress
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .installInProgress: "Wait for the Parakeet model installation to finish before recording."
            case .notInstalled: "Parakeet isn’t installed yet. Open Settings to download or import it."
            }
        }
    }
}
