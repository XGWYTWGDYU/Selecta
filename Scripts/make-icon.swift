import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let side = CGFloat(pixels)
        let tile = NSBezierPath(roundedRect: NSRect(x: side * 0.05, y: side * 0.05, width: side * 0.9, height: side * 0.9), xRadius: side * 0.2, yRadius: side * 0.2)
        NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.61, blue: 0.61, alpha: 1), ending: NSColor(calibratedRed: 0.1, green: 0.35, blue: 0.53, alpha: 1))!.draw(in: tile, angle: -60)
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .medium)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            symbol.draw(in: NSRect(x: side * 0.23, y: side * 0.22, width: side * 0.54, height: side * 0.54))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
