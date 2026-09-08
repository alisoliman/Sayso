import Foundation

/// A single, explicitly shared result. Only the containing app writes this mailbox.
/// The keyboard reads it with Full Access disabled and keeps consumption state in
/// its own sandbox. Neither audio nor the app's history is shared.
nonisolated struct KeyboardHandoff: Sendable {
    static let groupIdentifier = "group.solimanali.Sayso"
    static let lifetime: TimeInterval = 10 * 60
    static let maximumTextBytes = 64 * 1_024
    private static let maximumFileBytes = maximumTextBytes * 6 + 1_024

    struct Payload: Codable, Equatable, Sendable {
        let version: Int
        let id: UUID
        let text: String
        let createdAt: Date
        let expiresAt: Date

        /// Sharing the same dictation again creates a fresh, intentionally insertable handoff.
        var consumptionIdentifier: String { "\(id.uuidString):\(createdAt.timeIntervalSince1970)" }
    }

    enum HandoffError: LocalizedError {
        case unavailable, emptyText, tooLarge, invalidPayload

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Keyboard sharing isn’t available in this installation. You can still copy or share your text."
            case .emptyText:
                "There’s no text to send to the keyboard."
            case .tooLarge:
                "This result is too long for the keyboard. Copy or share it instead."
            case .invalidPayload:
                "This keyboard result couldn’t be read. Send the text again from Sayso."
            }
        }
    }

    private let fileURL: URL?

    init() {
        self.init(containerURL: FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupIdentifier
        ))
    }

    /// A nil URL is deliberately an error, not a fallback outside the App Group.
    init(containerURL: URL?) {
        fileURL = containerURL?.appending(path: "Keyboard", directoryHint: .isDirectory)
            .appending(path: "latest.json")
    }

    @discardableResult
    func publish(text: String, id: UUID = UUID(), now: Date = Date()) throws -> Payload {
        guard let fileURL else { throw HandoffError.unavailable }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HandoffError.emptyText
        }
        guard text.utf8.count <= Self.maximumTextBytes else { throw HandoffError.tooLarge }
        guard now.timeIntervalSince1970.isFinite else { throw HandoffError.invalidPayload }
        let payload = Payload(version: 1, id: id, text: text, createdAt: now,
                              expiresAt: now.addingTimeInterval(Self.lifetime))
        let data = try JSONEncoder().encode(payload)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var directory = fileURL.deletingLastPathComponent()
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try directory.setResourceValues(resourceValues)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        return payload
    }

    /// Reading never creates, deletes, or mutates anything in the shared container.
    func latest(now: Date = Date()) throws -> Payload? {
        guard let fileURL else { throw HandoffError.unavailable }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let byteCount = attributes[.size] as? NSNumber,
              byteCount.intValue <= Self.maximumFileBytes else { throw HandoffError.tooLarge }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: fileURL))
        } catch { throw HandoffError.invalidPayload }
        guard payload.version == 1,
              payload.text.utf8.count <= Self.maximumTextBytes,
              !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.createdAt.timeIntervalSince1970.isFinite,
              payload.expiresAt.timeIntervalSince1970.isFinite,
              payload.expiresAt.timeIntervalSince(payload.createdAt) == Self.lifetime else {
            throw HandoffError.invalidPayload
        }
        guard now >= payload.createdAt, now < payload.expiresAt else { return nil }
        return payload
    }

    /// The app can revoke its pending handoff without affecting saved dictations.
    func clear() throws {
        guard let fileURL else { throw HandoffError.unavailable }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Call from the containing app only. The read-only keyboard never purges files.
    func purgeExpired(now: Date = Date()) throws {
        guard let fileURL else { throw HandoffError.unavailable }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        // Reuse the bounded, validated reader before inspecting the expiry.
        guard try latest(now: now) == nil else { return }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: fileURL))
        if payload.expiresAt <= now { try clear() }
    }
}
