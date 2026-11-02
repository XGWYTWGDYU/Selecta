import AppKit
import Carbon

enum ShortcutAction: String, CaseIterable, Identifiable {
    case input, selection, screenshot, copyOCR
    var id: String { rawValue }
    var identifier: UInt32 { UInt32(Self.allCases.firstIndex(of: self)! + 1) }
    var title: String {
        switch self {
        case .input: return "输入翻译"
        case .selection: return "选词翻译"
        case .screenshot: return "截图翻译"
        case .copyOCR: return "截图 OCR 并复制"
        }
    }
}

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String
    var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }
    func matches(_ other: KeyboardShortcut) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    static let defaults: [String: KeyboardShortcut] = [
        "input": .init(keyCode: 0, modifiers: UInt32(optionKey), key: "A"),
        "selection": .init(keyCode: 2, modifiers: UInt32(optionKey), key: "D"),
        "screenshot": .init(keyCode: 1, modifiers: UInt32(optionKey), key: "S"),
        "copyOCR": .init(keyCode: 1, modifiers: UInt32(optionKey | shiftKey), key: "S")
    ]
    static func capture(_ event: NSEvent) -> KeyboardShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)] {
            if flags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        let labels: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 76: "⌤", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        return .init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: labels[event.keyCode] ?? characters.uppercased())
    }
}
