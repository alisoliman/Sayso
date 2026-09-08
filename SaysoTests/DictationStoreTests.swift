import XCTest
@testable import Sayso

@MainActor
final class DictationStoreTests: XCTestCase {
    private func workspace() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "SaysoStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func entry(_ text: String, date: Date = Date()) -> Dictation {
        Dictation(createdAt: date, text: text, original: "Original: \(text)", mode: .clean, duration: 3.5, localeIdentifier: "nl-NL")
    }

    func testSaveSurvivesReloadAndOrdersNewestFirst() throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "nested/dictations.json")
        let store = DictationStore(fileURL: url)
        let older = entry("First thought", date: Date(timeIntervalSince1970: 100))
        let newer = entry("A newer thought", date: Date(timeIntervalSince1970: 200))

        XCTAssertTrue(store.save(newer))
        XCTAssertTrue(store.save(older))

        let restored = DictationStore(fileURL: url)
        XCTAssertEqual(restored.entries, [newer, older])
        XCTAssertNil(restored.storageError)
    }

    func testEditingSameEntryIsIdempotentAndPreservesOriginal() throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "dictations.json")
        let store = DictationStore(fileURL: url)
        var original = entry("First version")
        XCTAssertTrue(store.save(original))
        original.text = "Edited version"
        original.mode = .message
        XCTAssertTrue(store.save(original))
        XCTAssertTrue(store.save(original))

        let restored = DictationStore(fileURL: url)
        XCTAssertEqual(restored.entries, [original])
        XCTAssertEqual(restored.entries.first?.original, "Original: First version")
    }

    func testDeleteAndDeleteAllPersistWithoutRemovingOtherEntries() throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "dictations.json")
        let store = DictationStore(fileURL: url)
        let first = entry("Keep this")
        let second = entry("Remove this")
        XCTAssertTrue(store.save(first))
        XCTAssertTrue(store.save(second))
        XCTAssertTrue(store.delete(second.id))
        XCTAssertTrue(store.delete(second.id))
        XCTAssertEqual(DictationStore(fileURL: url).entries, [first])

        XCTAssertTrue(store.deleteAll())
        XCTAssertTrue(DictationStore(fileURL: url).entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testFailedWriteKeepsCommittedMemoryAndDiskContents() throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appending(path: "storage", directoryHint: .isDirectory)
        let url = parent.appending(path: "dictations.json")
        let store = DictationStore(fileURL: url)
        let committed = entry("Already saved")
        XCTAssertTrue(store.save(committed))
        let committedData = try Data(contentsOf: url)

        // Replace the storage directory with a file: a deterministic filesystem write failure.
        let backup = directory.appending(path: "backup", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: parent, to: backup)
        let blocker = Data("This is a file, not a directory.".utf8)
        try blocker.write(to: parent)

        XCTAssertFalse(store.save(entry("Cannot be saved")))
        XCTAssertEqual(store.entries, [committed])
        XCTAssertNotNil(store.storageError)
        XCTAssertFalse(store.deleteAll())
        XCTAssertEqual(store.entries, [committed])
        XCTAssertEqual(try Data(contentsOf: backup.appending(path: "dictations.json")), committedData)
        XCTAssertEqual(try Data(contentsOf: parent), blocker)
    }

    func testCorruptReadPreservesFileAndRejectsAllMutations() throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "dictations.json")
        let unreadable = Data("[{\"text\":\"recoverable words\", interrupted write".utf8)
        try unreadable.write(to: url)

        let store = DictationStore(fileURL: url)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.storageError)
        XCTAssertFalse(store.save(entry("New words")))
        XCTAssertFalse(store.delete(UUID()))
        XCTAssertFalse(store.deleteAll())
        XCTAssertEqual(try Data(contentsOf: url), unreadable)
    }
}
