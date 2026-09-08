import XCTest
@testable import Sayso

final class KeyboardHandoffTests: XCTestCase {
    private var container: URL!
    private var mailbox: KeyboardHandoff!
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        mailbox = KeyboardHandoff(containerURL: container)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: container.path) {
            try FileManager.default.removeItem(at: container)
        }
    }

    func testExactTextRoundTripReplacementAndFreshConsumptionIdentity() throws {
        let text = "  Café 👋🏽\nمرحبا — 14:45\n"
        let id = UUID()
        let first = try mailbox.publish(text: text, id: id, now: date)
        XCTAssertEqual(try mailbox.latest(now: date)?.text, text)
        let replacement = try mailbox.publish(text: "Edited", id: id, now: date.addingTimeInterval(1))
        XCTAssertEqual(try mailbox.latest(now: date.addingTimeInterval(1)), replacement)
        XCTAssertNotEqual(first.consumptionIdentifier, replacement.consumptionIdentifier)
        let directory = container.appending(path: "Keyboard")
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testReadOnlyExpiryAndExplicitAppPurge() throws {
        XCTAssertNil(try mailbox.latest(now: date))
        XCTAssertFalse(FileManager.default.fileExists(atPath: container.path), "Read must not create a shared directory")
        try mailbox.publish(text: "A result", now: date)
        XCTAssertNotNil(try mailbox.latest(now: date.addingTimeInterval(599)))
        XCTAssertNil(try mailbox.latest(now: date.addingTimeInterval(600)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path), "Read-only keyboard cannot delete expired files")
        try mailbox.purgeExpired(now: date.addingTimeInterval(599))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))
        try mailbox.purgeExpired(now: date.addingTimeInterval(600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testInvalidPublicationDoesNotReplaceLastValidResult() throws {
        let original = try mailbox.publish(text: "Keep this", now: date)
        XCTAssertThrowsError(try mailbox.publish(text: " \n", now: date))
        XCTAssertThrowsError(try mailbox.publish(text: String(repeating: "😀", count: 16_385), now: date))
        XCTAssertEqual(try mailbox.latest(now: date), original)
        try mailbox.clear()
        try mailbox.clear()
        XCTAssertNil(try mailbox.latest(now: date))
        XCTAssertThrowsError(try KeyboardHandoff(containerURL: nil).latest())
        XCTAssertThrowsError(try KeyboardHandoff(containerURL: nil).publish(text: "No container"))
    }

    func testCorruptUnsupportedFutureAndOversizedHandoffsAreNotExposed() throws {
        let valid = try mailbox.publish(text: "Private text", now: date)
        XCTAssertNil(try mailbox.latest(now: date.addingTimeInterval(-1)), "Future handoffs are not eligible")
        try Data("{broken".utf8).write(to: payloadURL)
        XCTAssertThrowsError(try mailbox.latest(now: date))
        XCTAssertEqual(try Data(contentsOf: payloadURL), Data("{broken".utf8), "Read must preserve corrupt files")
        let unsupported = KeyboardHandoff.Payload(version: 2, id: valid.id, text: valid.text,
                                                  createdAt: date, expiresAt: valid.expiresAt)
        try JSONEncoder().encode(unsupported).write(to: payloadURL)
        XCTAssertThrowsError(try mailbox.latest(now: date))
        let tampered = KeyboardHandoff.Payload(version: 1, id: valid.id, text: valid.text,
                                               createdAt: date, expiresAt: date.addingTimeInterval(86_400))
        try JSONEncoder().encode(tampered).write(to: payloadURL)
        XCTAssertThrowsError(try mailbox.latest(now: date))
        try Data(repeating: 32, count: 400_000).write(to: payloadURL)
        XCTAssertThrowsError(try mailbox.latest(now: date))
    }

    func testFailedAtomicPublicationPreservesPreviousHandoff() throws {
        let original = try mailbox.publish(text: "Keep this result", now: date)
        let directory = payloadURL.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        XCTAssertThrowsError(try mailbox.publish(text: "Cannot replace", now: date.addingTimeInterval(1)))
        XCTAssertEqual(try mailbox.latest(now: date.addingTimeInterval(1)), original)
    }

    private var payloadURL: URL { container.appending(path: "Keyboard/latest.json") }
}
