import AppKit
import SwiftUI
import XCTest
@testable import Selecta

final class QueryEditorTests: XCTestCase {
    @MainActor
    func testNativeEditorDisplaysEditsAndSubmitsUnicodeText() throws {
        var value = "中文与 English"
        var submitted = false
        let binding = Binding(get: { value }, set: { value = $0 })
        let hosting = NSHostingView(rootView: QueryEditor(text: binding) { submitted = true })
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 120)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let editor = try XCTUnwrap(findEditor(hosting))
        XCTAssertEqual(editor.string, value)
        XCTAssertGreaterThan(editor.frame.height, 50)
        editor.insertText("新文本", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        XCTAssertEqual(value, "新文本")
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        editor.keyDown(with: event)
        XCTAssertTrue(submitted)
    }
    @MainActor
    private func findEditor(_ view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor($0) }.first
    }
}
