// Modified for Selecta: Swift port and reduced feature set, 2026-11-02.
// Selection strategy adapted from Easydict's AX-first / explicit-copy fallback workflow (GPL-3.0).
import AppKit
import ApplicationServices

@MainActor
enum SelectionReader {
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func read(from source: NSRunningApplication? = nil, allowCopy: Bool) async -> String? {
        guard AXIsProcessTrusted(), let app = source ?? NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.4)
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
           let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(focused, 0.4)
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subrole)
            if subrole as? String == kAXSecureTextFieldSubrole { return nil }
            var selected: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selected) == .success,
               let text = selected as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        guard allowCopy else { return nil }
        return await copySelection(application: application, pid: app.processIdentifier)
    }

    private static func copySelection(application: AXUIElement, pid: pid_t) async -> String? {
        let pasteboard = NSPasteboard.general
        let previous = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } }
        }
        let originalCount = pasteboard.changeCount
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, !Task.isCancelled else { return nil }
        // The actual Edit > Copy command works even while the translation shortcut is still held.
        if let copy = copyMenuItem(application) {
            AXUIElementPerformAction(copy, kAXPressAction as CFString)
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 25_000_000)
                if pasteboard.changeCount != originalCount || Task.isCancelled { break }
            }
        }
        if pasteboard.changeCount == originalCount {
            // Avoid sending Option-Command-C (or another combination) while the triggering key is held.
            let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            for _ in 0..<40 {
                if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty || Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            guard !Task.isCancelled,
                  CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else { return nil }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.postToPid(pid)
            up.postToPid(pid)
        }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pasteboard.changeCount != originalCount { break }
        }
        guard pasteboard.changeCount != originalCount else { return nil }
        let ownCount = pasteboard.changeCount
        let text = pasteboard.string(forType: .string)
        // Restore every data type, and never overwrite a newer copy operation.
        if pasteboard.changeCount == ownCount {
            pasteboard.clearContents()
            let items = previous.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                values.forEach { item.setData($0.1, forType: $0.0) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
    }

    private static func copyMenuItem(_ application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return findCopy(in: unsafeBitCast(value, to: AXUIElement.self), depth: 0)
    }

    private static func findCopy(in element: AXUIElement, depth: Int) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, 0.2)
        var key: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &key) == .success,
           (key as? String)?.lowercased() == "c" {
            var modifiers: CFTypeRef?
            var enabled: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modifiers)
            AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
            if (modifiers as? NSNumber)?.intValue == 0, (enabled as? NSNumber)?.boolValue == true { return element }
        }
        guard depth < 3 else { return nil }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in children as? [AXUIElement] ?? [] {
            if let copy = findCopy(in: child, depth: depth + 1) { return copy }
        }
        return nil
    }
}
