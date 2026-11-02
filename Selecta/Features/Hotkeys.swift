import Carbon
import Foundation

@MainActor
final class Hotkeys {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    var onAction: ((UInt32) -> Void)?

    func register(_ shortcuts: [String: KeyboardShortcut], paused: Bool = false) -> [String: String] {
        stop()
        guard !paused else { return [:] }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installation = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            let id = identifier.id
            DispatchQueue.main.async { owner.onAction?(id) }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installation == noErr else { return Dictionary(uniqueKeysWithValues: shortcuts.keys.map { ($0, "无法安装快捷键事件处理器。") }) }
        var failures: [String: String] = [:]
        for action in ShortcutAction.allCases {
            guard let shortcut = shortcuts[action.rawValue] else { continue }
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: 0x53454C41, id: action.identifier)
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references.append(reference) } else { failures[action.rawValue] = "\(shortcut.display) 被系统或其他程序占用，请重新设置。" }
        }
        return failures
    }
    func stop() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
