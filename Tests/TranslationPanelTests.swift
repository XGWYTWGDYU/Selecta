import AppKit
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
