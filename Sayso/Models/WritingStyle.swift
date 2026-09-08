import Foundation
import Observation

/// A saved writing mode. Stable IDs keep a renamed mode selected and preserve its history.
struct WritingStyle: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var prompt: String

    init(id: String = UUID().uuidString, title: String, prompt: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }

    static let defaults = WritingMode.allCases.map { mode in
        WritingStyle(id: mode.rawValue, title: mode.title, prompt: mode == .custom ? "" : mode.instructions)
    }

    var builtInMode: WritingMode? { WritingMode(rawValue: id) }
    var mode: WritingMode { builtInMode ?? .custom }
    var isBuiltIn: Bool { builtInMode != nil }
    var isOriginal: Bool { builtInMode == .transcript }
    var symbol: String { mode.symbol }
    var subtitle: String { isBuiltIn ? mode.subtitle : prompt }
    var isCustomized: Bool {
        guard let original = Self.defaults.first(where: { $0.id == id }) else { return false }
        return prompt != original.prompt
    }

    /// Edited prompts must choose their own output layout instead of inheriting Email/Notes rules.
    var transformationMode: WritingMode {
        if isOriginal { return .transcript }
        return isCustomized ? .custom : mode
    }
}

@MainActor @Observable
final class WritingStyleStore {
    private(set) var styles: [WritingStyle] = WritingStyle.defaults
    private(set) var storageError: String?
    private(set) var validationError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var canWrite = true
    private static let storageKey = "writingStyles"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.object(forKey: Self.storageKey) else {
            let legacy = defaults.string(forKey: "customInstructions")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !legacy.isEmpty, let index = styles.firstIndex(where: { $0.id == WritingMode.custom.rawValue }) {
                var migrated = styles
                migrated[index].prompt = legacy
                _ = persist(migrated)
            }
            return
        }

        do {
            guard let data = stored as? Data else { throw CatalogError.invalidData }
            let saved = try JSONDecoder().decode([WritingStyle].self, from: data)
            var restored = WritingStyle.defaults
            var ids = Set<String>()
            for style in saved {
                guard ids.insert(style.id).inserted,
                      !style.id.isEmpty,
                      !style.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      style.builtInMode == .custom || !style.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { throw CatalogError.invalidData }
                if let index = restored.firstIndex(where: { $0.id == style.id }) {
                    let original = restored[index]
                    guard style.title == original.title,
                          !style.isOriginal || style.prompt == original.prompt
                    else { throw CatalogError.invalidData }
                    restored[index] = style
                } else {
                    restored.append(style)
                }
            }
            guard Set(restored.map { Self.titleKey($0.title) }).count == restored.count else {
                throw CatalogError.invalidData
            }
            styles = restored
        } catch {
            canWrite = false
            storageError = "Your saved modes couldn’t be opened. They have been left untouched. You can still use the default modes."
        }
    }

    func style(for id: String) -> WritingStyle {
        styles.first(where: { $0.id == id }) ?? WritingStyle.defaults[0]
    }

    @discardableResult
    func save(_ style: WritingStyle) -> Bool {
        validationError = nil
        guard canWrite else { return false }
        var updatedStyle = style
        updatedStyle.title = style.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedStyle.prompt = style.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updatedStyle.isOriginal else { return invalid("Original always keeps your words untouched.") }
        guard !updatedStyle.id.isEmpty else { return invalid("This mode needs an identifier.") }
        guard !updatedStyle.title.isEmpty else { return invalid("Give this mode a name.") }
        guard !updatedStyle.prompt.isEmpty else { return invalid("Add writing instructions for this mode.") }
        if let builtIn = updatedStyle.builtInMode, updatedStyle.title != builtIn.title {
            return invalid("The names of the default modes can’t be changed.")
        }
        guard !styles.contains(where: {
            $0.id != updatedStyle.id && Self.titleKey($0.title) == Self.titleKey(updatedStyle.title)
        }) else { return invalid("A mode with this name already exists. Choose another name.") }

        var updated = styles
        if let index = updated.firstIndex(where: { $0.id == updatedStyle.id }) {
            updated[index] = updatedStyle
        } else {
            updated.append(updatedStyle)
        }
        return persist(updated)
    }

    @discardableResult
    func delete(_ style: WritingStyle) -> Bool {
        validationError = nil
        guard canWrite else { return false }
        guard !style.isBuiltIn else { return invalid("Default modes can’t be deleted.") }
        guard styles.contains(where: { $0.id == style.id }) else { return invalid("This mode no longer exists.") }
        guard persist(styles.filter { $0.id != style.id }) else { return false }
        if defaults.string(forKey: "writingMode") == style.id {
            defaults.set(WritingMode.transcript.rawValue, forKey: "writingMode")
        }
        return true
    }

    @discardableResult
    func reset(_ style: WritingStyle) -> Bool {
        validationError = nil
        guard canWrite else { return false }
        guard !style.isOriginal else { return invalid("Original always keeps your words untouched.") }
        guard let original = WritingStyle.defaults.first(where: { $0.id == style.id }),
              let index = styles.firstIndex(where: { $0.id == style.id })
        else { return invalid("Only default modes can be reset.") }
        var updated = styles
        updated[index] = original
        return persist(updated)
    }

    private func persist(_ updated: [WritingStyle]) -> Bool {
        guard canWrite else { return false }
        do {
            // Store only overrides so future built-in prompt improvements remain available.
            let saved = updated.filter { style in
                !WritingStyle.defaults.contains(style)
            }
            let data = try JSONEncoder().encode(saved)
            defaults.set(data, forKey: Self.storageKey)
            styles = updated
            storageError = nil
            return true
        } catch {
            storageError = "Your modes couldn’t be saved. Please try again."
            return false
        }
    }

    private func invalid(_ message: String) -> Bool {
        validationError = message
        return false
    }

    private static func titleKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private enum CatalogError: Error { case invalidData }
}
