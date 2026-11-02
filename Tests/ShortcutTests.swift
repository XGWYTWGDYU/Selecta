import AppKit
import Carbon
import XCTest
@testable import Selecta

final class ShortcutTests: XCTestCase {
    @MainActor
    func testShortcutChangesAndDisablingSurviveRestart() throws {
        let name = "SelectaShortcuts-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let shortcut = KeyboardShortcut(keyCode: 3, modifiers: UInt32(cmdKey | shiftKey), key: "F")
        try preferences.setShortcut(shortcut, for: .selection)
        try preferences.setShortcut(nil, for: .screenshot)
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.shortcut(.selection), shortcut)
        XCTAssertNil(restored.shortcut(.screenshot))
        XCTAssertEqual(restored.shortcut(.input), KeyboardShortcut.defaults["input"])
        restored.restoreShortcuts()
        XCTAssertEqual(restored.shortcuts, KeyboardShortcut.defaults)
    }
    @MainActor
    func testDuplicatePhysicalCombinationIsRejectedWithoutChangingBindings() throws {
        let name = "SelectaDuplicates-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let before = preferences.shortcuts
        let sameKeyWithDifferentLabel = KeyboardShortcut(keyCode: 0, modifiers: UInt32(optionKey), key: "a")
        XCTAssertThrowsError(try preferences.setShortcut(sameKeyWithDifferentLabel, for: .selection))
        XCTAssertEqual(preferences.shortcuts, before)
    }
    @MainActor
    func testRecorderCapturesCommandCombinationAndEscapeCancels() throws {
        let button = RecorderButton()
        var captured: KeyboardShortcut?
        var recording = false
        button.onChange = { captured = $0 }
        button.onRecording = { recording = $0 }
        button.beginRecording()
        XCTAssertTrue(recording)
        button.keyDown(with: try event(keyCode: 3, flags: [.command, .shift], characters: "F"))
        XCTAssertEqual(captured?.display, "⇧⌘F")
        XCTAssertFalse(recording)
        button.beginRecording()
        button.keyDown(with: try event(keyCode: 53, flags: [], characters: "\u{1b}"))
        XCTAssertEqual(captured?.display, "⇧⌘F")
        XCTAssertFalse(recording)
    }
    @MainActor
    func testUnmodifiedTypingCannotBecomeGlobalShortcut() throws {
        XCTAssertNil(KeyboardShortcut.capture(try event(keyCode: 0, flags: [], characters: "a")))
        XCTAssertNil(KeyboardShortcut.capture(try event(keyCode: 0, flags: [.shift], characters: "A")))
    }
    @MainActor
    private func event(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }
}
