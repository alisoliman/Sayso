import Foundation
import Observation

struct Dictation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var text: String
    let original: String
    var mode: WritingMode
    var duration: TimeInterval
    var localeIdentifier: String
    var title: String { String(text.split(separator: "\n", omittingEmptySubsequences: true).first ?? "Untitled") }
    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

@MainActor @Observable
final class DictationStore {
    private(set) var entries: [Dictation] = []
    private(set) var storageError: String?
    /// The controller reconciles its visible result only after a durable store mutation.
    @ObservationIgnored var onEntriesChanged: (([Dictation], [Dictation]) -> Void)?
    private let fileURL: URL
    private var canWrite = true

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "Sayso", directoryHint: .isDirectory).appending(path: "dictations.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                entries = try JSONDecoder().decode([Dictation].self, from: Data(contentsOf: self.fileURL)).sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            canWrite = false
            storageError = "Your saved dictations couldn’t be opened. They have been left untouched. New text can still be copied or shared."
        }
    }

    @discardableResult func save(_ entry: Dictation) -> Bool {
        var updated = entries.filter { $0.id != entry.id }
        updated.append(entry)
        updated.sort { $0.createdAt > $1.createdAt }
        return persist(updated)
    }
    @discardableResult func delete(_ id: UUID) -> Bool { persist(entries.filter { $0.id != id }) }
    @discardableResult func deleteAll() -> Bool { persist([]) }

    private func persist(_ updated: [Dictation]) -> Bool {
        guard canWrite else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            let previous = entries
            entries = updated
            storageError = nil
            onEntriesChanged?(previous, updated)
            return true
        } catch {
            storageError = "This dictation couldn’t be saved. Copy or share your text before closing Sayso."
            return false
        }
    }
}

enum SpeechLanguage {
    static let choices: [(id: String, name: String)] = [
        ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("nl-NL", "Nederlands"),
        ("ar-SA", "العربية"), ("de-DE", "Deutsch"), ("fr-FR", "Français"),
        ("es-ES", "Español"), ("it-IT", "Italiano"), ("pt-BR", "Português"),
        ("ja-JP", "日本語"), ("ko-KR", "한국어"), ("zh-CN", "简体中文")
    ]
    static var defaultIdentifier: String {
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        let language = Locale(identifier: preferred).language.languageCode?.identifier
        return choices.first { $0.id == preferred }?.id
            ?? choices.first { Locale(identifier: $0.id).language.languageCode?.identifier == language }?.id ?? "en-US"
    }
    static func name(for identifier: String) -> String {
        choices.first { $0.id == identifier }?.name ?? Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
    static func shortName(for identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier.uppercased() ?? "EN"
    }
}
