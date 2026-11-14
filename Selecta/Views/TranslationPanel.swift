// Modified for Selecta: Swift port and reduced feature set, 2026-11-02.
// Swift port of Easydict's EZMiniQueryWindow / EZBaseQueryWindow (GPL-3.0).
// Copyright © 2022–2026 izual and contributors.
import AppKit

final class TranslationPanel: NSPanel {
    var placementAnchor: NSPoint?
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 165),
                   styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 360, height: 165)
        collectionBehavior = [.ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating
    }
    func present(at anchor: NSPoint?, in visibleFrame: NSRect, activate: Bool) {
        if let anchor { placementAnchor = anchor }
        let desired = NSSize(width: frame.width, height: frame.height)
        let placement = PopupPlacement.frame(size: desired, anchor: anchor, current: frame, visibleFrame: visibleFrame)
        setFrame(placement, display: true)
        // Pinning controls dismissal, not visibility above the originating app.
        level = .floating
        orderFrontRegardless()
        if activate {
            makeKeyAndOrderFront(nil)
        }
    }
    /// The panel never activates Selecta, so the main menu's Edit shortcuts are not dispatched to it.
    /// Route the standard editing commands to the first responder directly (query editor, selectable results).
    static func editingAction(for event: NSEvent) -> Selector? {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
        case (.command, "x"): return #selector(NSText.cut(_:))
        case (.command, "c"): return #selector(NSText.copy(_:))
        case (.command, "v"): return #selector(NSText.paste(_:))
        case (.command, "a"): return #selector(NSText.selectAll(_:))
        case (.command, "z"): return Selector(("undo:"))
        case ([.command, .shift], "z"): return Selector(("redo:"))
        default: return nil
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard let action = Self.editingAction(for: event) else { return false }
        // NSApp.keyWindow can be nil while Selecta is inactive, so walk this panel's responder chain.
        return (firstResponder ?? self).tryToPerform(action, with: self)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}
