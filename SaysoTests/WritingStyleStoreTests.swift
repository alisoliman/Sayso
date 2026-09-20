import XCTest
@testable import Sayso

@MainActor
final class WritingStyleStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WritingStyleStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsPreserveLegacyModeIDsAndEmptyCustom() {
        let store = WritingStyleStore(defaults: defaults)
        XCTAssertEqual(store.styles.map(\.id), WritingMode.allCases.map(\.rawValue))
        XCTAssertEqual(store.style(for: "custom").prompt, "")
        XCTAssertEqual(store.style(for: "missing").mode, .transcript)
        for style in store.styles {
            XCTAssertEqual(style.transformationMode, style.mode)
        }
    }

    func testLegacyCustomInstructionsMigrateOnceAndSavedCatalogTakesPrecedence() {
        defaults.set("  Write in short paragraphs.\n", forKey: "customInstructions")
        defaults.set("custom", forKey: "writingMode")

        let store = WritingStyleStore(defaults: defaults)
        XCTAssertEqual(store.style(for: "custom").prompt, "Write in short paragraphs.")
        XCTAssertEqual(defaults.string(forKey: "writingMode"), "custom")
        XCTAssertEqual(WritingStyleStore(defaults: defaults).styles, store.styles)

        // A previously saved empty override catalog must not reimport old preferences.
        defaults.set(Data("[]".utf8), forKey: "writingStyles")
        XCTAssertEqual(WritingStyleStore(defaults: defaults).style(for: "custom").prompt, "")
        XCTAssertEqual(defaults.string(forKey: "customInstructions"), "  Write in short paragraphs.\n")
    }

    func testNewModesAndBuiltinEditsRoundTripWithStableOrderAndIDs() throws {
        let store = WritingStyleStore(defaults: defaults)
        var email = store.style(for: "email")
        email.prompt = "Write numbered steps."
        let first = WritingStyle(title: "  Brief  ", prompt: "  Use short paragraphs.\n")
        let second = WritingStyle(title: "Checklist", prompt: "Use one bullet per action.")
        XCTAssertNotNil(UUID(uuidString: first.id))
        XCTAssertTrue(store.save(first))
        XCTAssertTrue(store.save(email))
        XCTAssertTrue(store.save(second))
        var renamed = store.style(for: first.id)
        renamed.title = "Concise"
        defaults.set(first.id, forKey: "writingMode")
        XCTAssertTrue(store.save(renamed))

        let restored = WritingStyleStore(defaults: defaults)
        XCTAssertEqual(restored.styles, store.styles)
        XCTAssertEqual(restored.styles.suffix(2).map(\.id), [first.id, second.id])
        XCTAssertEqual(restored.style(for: first.id).prompt, "Use short paragraphs.")
        XCTAssertEqual(defaults.string(forKey: "writingMode"), first.id)
        XCTAssertNil(restored.storageError)
        let encoded = try XCTUnwrap(defaults.data(forKey: "writingStyles"))
        XCTAssertEqual(try JSONDecoder().decode([WritingStyle].self, from: encoded).count, 3)
    }

    func testEditedBuiltinsUseCustomLayoutAndSavingDefaultPromptRestoresRouting() {
        let store = WritingStyleStore(defaults: defaults)
        for mode in [WritingMode.email, .notes, .clean, .message] {
            var style = store.style(for: mode.rawValue)
            style.prompt = "Rewrite as a single paragraph."
            XCTAssertTrue(store.save(style))
            XCTAssertEqual(store.style(for: style.id).mode, mode)
            XCTAssertEqual(store.style(for: style.id).transformationMode, .custom)
            XCTAssertTrue(store.style(for: style.id).isCustomized)
            style.prompt = mode.instructions
            XCTAssertTrue(store.save(style))
            XCTAssertEqual(store.style(for: style.id).prompt, mode.instructions)
            XCTAssertEqual(store.style(for: style.id).transformationMode, mode)
        }
        let custom = WritingStyle(title: "My mode", prompt: "Write in paragraphs.")
        XCTAssertEqual(custom.mode, .custom)
        XCTAssertEqual(custom.transformationMode, .custom)
    }

    func testDeletingSelectedModeFallsBackToOriginalAndKeepsOthers() {
        let store = WritingStyleStore(defaults: defaults)
        let first = WritingStyle(title: "First", prompt: "Use bullets.")
        let second = WritingStyle(title: "Second", prompt: "Use numbered steps.")
        XCTAssertTrue(store.save(first))
        XCTAssertTrue(store.save(second))
        defaults.set(second.id, forKey: "writingMode")
        XCTAssertTrue(store.delete(first))
        XCTAssertEqual(defaults.string(forKey: "writingMode"), second.id)
        XCTAssertTrue(store.delete(second))
        XCTAssertEqual(defaults.string(forKey: "writingMode"), "transcript")
        XCTAssertEqual(WritingStyleStore(defaults: defaults).styles, WritingStyle.defaults)
    }

    func testInvalidAndDuplicateValuesLeaveCommittedCatalogUntouched() {
        let store = WritingStyleStore(defaults: defaults)
        let valid = WritingStyle(title: "Brief", prompt: "Use short sentences.")
        XCTAssertTrue(store.save(valid))
        let committed = store.styles
        let data = defaults.data(forKey: "writingStyles")
        let invalid = [
            WritingStyle(title: " \n", prompt: "Write clearly."),
            WritingStyle(title: "Blank", prompt: " \n"),
            WritingStyle(title: " brief ", prompt: "Write clearly."),
            WritingStyle(title: "EMAIL", prompt: "Write clearly."),
            WritingStyle(id: "email", title: "Renamed email", prompt: "Write clearly."),
            WritingStyle(id: "transcript", title: "Original", prompt: "Change my words."),
            WritingStyle(id: "custom", title: "Custom", prompt: ""),
        ]
        for style in invalid {
            XCTAssertFalse(store.save(style))
            XCTAssertNotNil(store.validationError)
            XCTAssertEqual(store.styles, committed)
            XCTAssertEqual(defaults.data(forKey: "writingStyles"), data)
        }
        XCTAssertTrue(store.save(valid), "Saving a mode with its own existing name is valid.")
        XCTAssertNil(store.validationError)
        for mode in WritingMode.allCases {
            XCTAssertFalse(store.delete(store.style(for: mode.rawValue)))
        }
    }

    func testCorruptStorageIsPreservedAndRejectsEveryMutation() {
        let unreadable = Data("[{\"title\":\"My writing\", incomplete".utf8)
        defaults.set(unreadable, forKey: "writingStyles")
        defaults.set("Legacy instructions", forKey: "customInstructions")
        let store = WritingStyleStore(defaults: defaults)
        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(store.styles, WritingStyle.defaults)
        XCTAssertFalse(store.save(WritingStyle(title: "New", prompt: "Write clearly.")))
        XCTAssertFalse(store.delete(WritingStyle(title: "New", prompt: "Write clearly.")))
        XCTAssertFalse(store.save(store.style(for: "email")))
        XCTAssertEqual(defaults.data(forKey: "writingStyles"), unreadable)
    }

    func testSemanticallyInvalidCatalogIsProtected() throws {
        let invalidCatalogs = [
            [WritingStyle(title: "Email", prompt: "Write clearly.")],
            [WritingStyle(title: "No prompt", prompt: "")],
            [WritingStyle(id: "email", title: "Renamed", prompt: "Write clearly.")],
            [WritingStyle(id: "transcript", title: "Original", prompt: "Rewrite everything.")],
            [WritingStyle(id: "same", title: "One", prompt: "A"), WritingStyle(id: "same", title: "Two", prompt: "B")],
        ]
        for catalog in invalidCatalogs {
            let data = try JSONEncoder().encode(catalog)
            defaults.set(data, forKey: "writingStyles")
            let store = WritingStyleStore(defaults: defaults)
            XCTAssertNotNil(store.storageError)
            XCTAssertFalse(store.save(WritingStyle(title: "New", prompt: "Write clearly.")))
            XCTAssertEqual(defaults.data(forKey: "writingStyles"), data)
        }
        defaults.set("Wrong storage type", forKey: "writingStyles")
        XCTAssertNotNil(WritingStyleStore(defaults: defaults).storageError)
        XCTAssertEqual(defaults.string(forKey: "writingStyles"), "Wrong storage type")
    }
}
