import AppKit
import SwiftUI
import XCTest
@testable import Selecta

final class TranslationPanelTests: XCTestCase {
    @MainActor
    func testOriginalMiniWindowContract() {
        let panel = TranslationPanel()
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.frame.width, 420)
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertEqual(panel.contentView?.safeAreaInsets.top, 0)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.isMovableByWindowBackground)
    }
    @MainActor
    func testPresentationBringsAnAlreadyVisiblePopupBackOnScreen() {
        let panel = TranslationPanel()
        defer { panel.orderOut(nil) }
        let bounds = NSRect(x: 0, y: 0, width: 1440, height: 850)
        panel.setFrame(NSRect(x: 3000, y: -800, width: 420, height: 300), display: false)
        panel.orderFrontRegardless()
        panel.present(at: NSPoint(x: 1400, y: 800), in: bounds, activate: false)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(bounds.contains(panel.frame))
        XCTAssertEqual(panel.level, .floating)
    }
    @MainActor
    func testEditingShortcutsWorkWithoutActivatingTheApp() throws {
        let panel = TranslationPanel()
        defer { panel.orderOut(nil) }
        var value = ""
        let binding = Binding(get: { value }, set: { value = $0 })
        let hosting = NSHostingView(rootView: QueryEditor(text: binding) {})
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let editor = try XCTUnwrap(findEditor(hosting))
        XCTAssertTrue(panel.makeFirstResponder(editor))
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer { pasteboard.clearContents(); if let saved { pasteboard.setString(saved, forType: .string) } }
        pasteboard.clearContents()
        pasteboard.setString("粘贴 paste", forType: .string)
        func key(_ character: String, _ modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: panel.windowNumber,
                                           context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0))
        }
        XCTAssertTrue(panel.performKeyEquivalent(with: try key("v")))
        XCTAssertEqual(editor.string, "粘贴 paste")
        XCTAssertEqual(value, "粘贴 paste")
        XCTAssertTrue(panel.performKeyEquivalent(with: try key("a")))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (editor.string as NSString).length))
        XCTAssertTrue(panel.performKeyEquivalent(with: try key("z")))
        XCTAssertEqual(editor.string, "")
        XCTAssertFalse(panel.performKeyEquivalent(with: try key("v", [.command, .option])), "Unrelated combinations stay unhandled")
    }
    @MainActor
    private func findEditor(_ view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor($0) }.first
    }
    @MainActor
    func testReopenDoesNotCreateAnyWindows() {
        let name = "SelectaReopen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let delegate = AppDelegate(preferences: Preferences(defaults: defaults))
        let before = NSApp.windows.count
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertEqual(NSApp.windows.count, before)
    }
}
