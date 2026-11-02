import AppKit

enum PopupPlacement {
    static func frame(size: NSSize, anchor: NSPoint?, current: NSRect, visibleFrame bounds: NSRect) -> NSRect {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        let proposed = anchor.map { NSPoint(x: $0.x, y: bounds.minY + bounds.height * 0.6 - height / 2) }
            ?? NSPoint(x: current.minX, y: current.maxY - height)
        return NSRect(x: max(bounds.minX, min(proposed.x, bounds.maxX - width)),
                      y: max(bounds.minY, min(proposed.y, bounds.maxY - height)),
                      width: width, height: height)
    }
}
