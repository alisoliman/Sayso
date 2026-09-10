import Foundation

/// Metadata and explicit controls for one ongoing dictation. Contains no audio,
/// transcript, clipboard content, or surrounding text from the destination app.
nonisolated struct KeyboardRecordingSessionStore: Sendable {
    static let recordingLimit: TimeInterval = 10 * 60
    static let completionAllowance: TimeInterval = 60
    static let heartbeatLifetime: TimeInterval = 15

    enum Phase: String, Codable, Sendable {
        case recording, finishing, refining
    }
    enum Action: String, Codable, Sendable { case stop, cancel }
    struct Mode: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let symbol: String
    }
    struct Session: Codable, Equatable, Sendable {
        let version: Int
        let id: UUID
        let startedAt: Date
        let recordingEndsAt: Date
        var updatedAt: Date
        var phase: Phase
        var availableModes: [Mode]? = nil
        var selectedModeID: String? = nil
    }
    struct Command: Codable, Equatable, Sendable {
        let version: Int
        let id: UUID
        let sessionID: UUID
        let action: Action
        let createdAt: Date
        var modeID: String? = nil
    }
    enum SessionError: LocalizedError {
        case unavailable, noActiveSession, invalidData
        var errorDescription: String? {
            switch self {
            case .unavailable: "Recording controls aren’t available in this installation. Open Sayso to finish."
            case .noActiveSession: "This recording is no longer active. Open Sayso to start another."
            case .invalidData: "The recording status couldn’t be read. Open Sayso to finish."
            }
        }
    }

    private let directory: URL?
    init() {
        self.init(containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KeyboardHandoff.groupIdentifier))
    }
    init(containerURL: URL?) { directory = containerURL?.appending(path: "Recording", directoryHint: .isDirectory) }

    @discardableResult
    func begin(sessionID: UUID, availableModes: [Mode]? = nil, selectedModeID: String? = nil, now: Date = Date()) throws -> Session {
        guard now.timeIntervalSince1970.isFinite else { throw SessionError.invalidData }
        let session = Session(version: 1, id: sessionID, startedAt: now,
                              recordingEndsAt: now.addingTimeInterval(Self.recordingLimit), updatedAt: now, phase: .recording,
                              availableModes: availableModes, selectedModeID: selectedModeID)
        try validate(session)
        return try withMutation {
            // Clear before publishing, while excluding senders. A Stop issued as
            // soon as the new session becomes visible must never be erased.
            try remove(name: "command.json")
            try write(session, name: "session.json")
            return session
        }
    }

    func latest(now: Date = Date()) throws -> Session? {
        guard let session: Session = try read(name: "session.json") else { return nil }
        try validate(session)
        guard isLive(session, now: now) else { return nil }
        return session
    }

    @discardableResult
    func update(sessionID: UUID, phase: Phase, now: Date = Date()) throws -> Session {
        try withMutation {
            guard var session: Session = try read(name: "session.json"), session.id == sessionID else {
                throw SessionError.noActiveSession
            }
            try validate(session)
            guard isLive(session, now: now) else { throw SessionError.noActiveSession }
            // A delayed heartbeat cannot turn a finishing session into recording.
            guard phaseOrder(phase) >= phaseOrder(session.phase) else { throw SessionError.invalidData }
            session.updatedAt = now
            session.phase = phase
            try write(session, name: "session.json")
            return session
        }
    }

    /// Called only after an explicit keyboard/Live Activity action. The keyboard
    /// must have Full Access before invoking this write; the widget uses its group entitlement.
    func send(_ action: Action, sessionID: UUID, modeID: String? = nil, now: Date = Date()) throws {
        try withMutation {
            guard let session = try latest(now: now), session.id == sessionID else { throw SessionError.noActiveSession }
            if action == .stop {
                guard session.phase == .recording else { return }
                if let modeID, session.availableModes?.contains(where: { $0.id == modeID }) != true {
                    throw SessionError.invalidData
                }
                // Discard wins over a nearly simultaneous Stop from another surface.
                if let pending: Command = try read(name: "command.json"),
                   isValid(pending, for: session, now: now), pending.action == .cancel { return }
            }
            try write(Command(version: 1, id: UUID(), sessionID: sessionID, action: action, createdAt: now,
                              modeID: action == .stop ? modeID : nil), name: "command.json")
        }
    }

    /// The host acknowledges a command by ID in memory. Reads never delete a
    /// newer command that may have replaced the one just observed.
    func command(sessionID: UUID, after commandID: UUID?, now: Date = Date()) throws -> Command? {
        try withRead {
            guard let session = try latest(now: now), session.id == sessionID,
                  let command: Command = try read(name: "command.json") else { return nil }
            guard command.version == 1, command.createdAt.timeIntervalSince1970.isFinite else {
                throw SessionError.invalidData
            }
            guard isValid(command, for: session, now: now), command.id != commandID else { return nil }
            return command
        }
    }

    /// Linearizes publication with explicit cancellation. The caller's commit
    /// must be synchronous and must not call back into this session store.
    /// Ownership remains valid for cleanup after lease expiry; no lease is renewed.
    /// Returns false when an accepted Cancel wins, without executing the commit.
    func complete(sessionID: UUID, now: Date = Date(), commit: () throws -> Void) throws -> Bool {
        try withMutation {
            guard let session: Session = try read(name: "session.json"), session.id == sessionID else {
                throw SessionError.noActiveSession
            }
            try validate(session)
            guard now.timeIntervalSince1970.isFinite, now >= session.updatedAt else { throw SessionError.invalidData }
            let pending: Command? = try read(name: "command.json")
            let cancelled = pending.map { isValid($0, for: session, now: now) && $0.action == .cancel } ?? false
            if !cancelled {
                // A throwing commit leaves both metadata files untouched so the
                // caller can report its failure and perform explicit cleanup.
                try commit()
            }
            // Close ownership first. Even if removal of leftover metadata fails,
            // no later sender may submit controls for an already committed result.
            try remove(name: "session.json")
            try remove(name: "command.json")
            return !cancelled
        }
    }

    /// Ends only this session, even if a delayed cleanup races a newer recording.
    func end(sessionID: UUID) throws {
        try withMutation {
            guard let session: Session = try read(name: "session.json"), session.id == sessionID else { return }
            // All command writers use the same coordination scope. No newer
            // session or command can appear between the ID check and cleanup.
            try remove(name: "command.json")
            try remove(name: "session.json")
        }
    }

    private func validate(_ session: Session) throws {
        guard session.version == 1,
              session.startedAt.timeIntervalSince1970.isFinite, session.updatedAt.timeIntervalSince1970.isFinite,
              session.recordingEndsAt.timeIntervalSince(session.startedAt) == Self.recordingLimit,
              session.updatedAt >= session.startedAt,
              session.updatedAt <= session.recordingEndsAt.addingTimeInterval(Self.completionAllowance) else {
            throw SessionError.invalidData
        }
        if let modes = session.availableModes {
            guard modes.count <= 24, Set(modes.map(\.id)).count == modes.count,
                  modes.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 128 &&
                      !$0.title.isEmpty && $0.title.utf8.count <= 120 && $0.symbol.utf8.count <= 80 }),
                  session.selectedModeID == nil || modes.contains(where: { $0.id == session.selectedModeID }) else {
                throw SessionError.invalidData
            }
        } else if session.selectedModeID != nil { throw SessionError.invalidData }
    }

    private func isLive(_ session: Session, now: Date) -> Bool {
        now.timeIntervalSince1970.isFinite && now >= session.startedAt && now >= session.updatedAt &&
        now.timeIntervalSince(session.updatedAt) <= Self.heartbeatLifetime &&
        now <= session.recordingEndsAt.addingTimeInterval(Self.completionAllowance)
    }

    private func isValid(_ command: Command, for session: Session, now: Date) -> Bool {
        command.version == 1 && command.createdAt.timeIntervalSince1970.isFinite &&
        (command.modeID == nil || (command.action == .stop && session.availableModes?.contains(where: { $0.id == command.modeID }) == true)) &&
        command.sessionID == session.id && command.createdAt >= session.startedAt &&
        command.createdAt <= now &&
        // An accepted cancellation is terminal for its recording, even when the
        // host resumes much later. The lease only gates submission of new controls.
        (command.action == .cancel || now.timeIntervalSince(command.createdAt) <= Self.heartbeatLifetime)
    }

    private func phaseOrder(_ phase: Phase) -> Int {
        switch phase { case .recording: 0; case .finishing: 1; case .refining: 2 }
    }

    /// App and extension processes must coordinate the whole read/modify/write,
    /// not just their individual atomic replacements. No file presenter is kept.
    private func withMutation<T>(_ operation: () throws -> T) throws -> T {
        guard var directory else { throw SessionError.unavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        var error: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: directory, options: [], error: &error) { _ in
            result = Result { try operation() }
        }
        if let error { throw error }
        guard let result else { throw SessionError.unavailable }
        return try result.get()
    }

    private func withRead<T>(_ operation: () throws -> T) throws -> T {
        guard let directory else { throw SessionError.unavailable }
        // Reading an unconfigured keyboard must not create a shared directory.
        guard FileManager.default.fileExists(atPath: directory.path) else { return try operation() }
        var error: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: directory, options: [], error: &error) { _ in
            result = Result { try operation() }
        }
        if let error { throw error }
        guard let result else { throw SessionError.unavailable }
        return try result.get()
    }

    private func file(_ name: String) throws -> URL {
        guard let directory else { throw SessionError.unavailable }
        return directory.appending(path: name)
    }
    private func read<T: Decodable>(name: String) throws -> T? {
        let url = try file(name)
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch let error as NSError where
            (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)) ||
            (error.domain == NSPOSIXErrorDomain && error.code == Int(POSIXErrorCode.ENOENT.rawValue)) { return nil }
        defer { try? handle.close() }
        // Open one inode, then read at most the bound plus one. A racing atomic
        // replacement cannot turn a checked small file into an unbounded read.
        var data = Data()
        while data.count <= 8_192 {
            guard let chunk = try handle.read(upToCount: 8_193 - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= 8_192 else { throw SessionError.invalidData }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw SessionError.invalidData }
    }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        let url = try file(name)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8_192 else { throw SessionError.invalidData }
        // Only recording metadata and commands use this class. It allows the
        // already-active app to read an authenticated Lock Screen stop command.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func remove(name: String) throws {
        let url = try file(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
