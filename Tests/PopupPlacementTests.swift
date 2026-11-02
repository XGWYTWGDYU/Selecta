import AppKit
import XCTest
@testable import Selecta

final class PopupPlacementTests: XCTestCase {
    func testLeftEdgeUsesMouseXAndCentersAboveScreenMidpoint() {
        let bounds = NSRect(x: 0, y: 30, width: 1440, height: 850)
        let frame = PopupPlacement.frame(size: NSSize(width: 420, height: 300), anchor: NSPoint(x: 200, y: 100), current: .zero, visibleFrame: bounds)
        XCTAssertEqual(frame.minX, 200)
        XCTAssertEqual(frame.midY, bounds.minY + bounds.height * 0.6)
        let otherMouseHeight = PopupPlacement.frame(size: frame.size, anchor: NSPoint(x: 200, y: 800), current: .zero, visibleFrame: bounds)
        XCTAssertEqual(frame, otherMouseHeight)
    }
    func testEveryScreenEdgeKeepsEntireWindowVisible() {
        let bounds = NSRect(x: 0, y: 40, width: 1440, height: 820)
        for anchor in [NSPoint(x: 0, y: 40), NSPoint(x: 1440, y: 40), NSPoint(x: 0, y: 860), NSPoint(x: 1440, y: 860)] {
            let frame = PopupPlacement.frame(size: NSSize(width: 420, height: 400), anchor: anchor, current: .zero, visibleFrame: bounds)
            XCTAssertTrue(bounds.contains(frame), "\(anchor): \(frame)")
        }
    }
    func testSecondaryDisplaysWithNegativeCoordinatesAndOversizedWindows() {
        let bounds = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let frame = PopupPlacement.frame(size: NSSize(width: 2600, height: 1400), anchor: NSPoint(x: -10, y: -180), current: .zero, visibleFrame: bounds)
        XCTAssertEqual(frame, bounds)
    }
    func testContentResizePreservesTopEdgeAndClampsToScreen() {
        let bounds = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let current = NSRect(x: 700, y: 400, width: 420, height: 200)
        let compact = PopupPlacement.frame(size: NSSize(width: 420, height: 165), anchor: nil, current: current, visibleFrame: bounds)
        XCTAssertEqual(compact.maxY, current.maxY)
        let large = PopupPlacement.frame(size: NSSize(width: 420, height: 750), anchor: nil, current: current, visibleFrame: bounds)
        XCTAssertTrue(bounds.contains(large))
    }
    func testReturnedResultsAndErrorsExpandBeyondInputHeight() {
        let empty = PopupLayout.contentHeight(input: "Hello", notice: nil, results: [:], collapsed: [], width: 420)
        let translated = PopupLayout.contentHeight(input: "Hello", notice: nil, results: [.google: .success("你好"), .deepL: .success("您好")], collapsed: [], width: 420)
        XCTAssertEqual(empty, 165)
        XCTAssertGreaterThan(translated, 280)
        let collapsed = PopupLayout.contentHeight(input: "Hello", notice: nil, results: [.google: .success("你好"), .deepL: .success("您好")], collapsed: [.google, .deepL], width: 420)
        XCTAssertLessThan(collapsed, translated)
        let error = PopupLayout.contentHeight(input: "", notice: String(repeating: "读取失败，请重试。", count: 12), results: [:], collapsed: [], width: 360)
        XCTAssertGreaterThan(error, empty)
    }
}
