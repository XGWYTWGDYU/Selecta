import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut?
    let onChange: (KeyboardShortcut?) -> Void
    let onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onChange = onChange
        button.onRecording = onRecording
        button.shortcut = shortcut
        if !button.recording { button.title = shortcut?.display ?? "点击录制" }
        button.setAccessibilityLabel("快捷键：\(shortcut?.display ?? "未设置")，点击后按下新的组合键")
    }
}

final class RecorderButton: NSButton {
    var onChange: ((KeyboardShortcut?) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var shortcut: KeyboardShortcut?
    private(set) var recording = false
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() {
        finish()
        window?.makeFirstResponder(self)
        recording = true
        title = "请按组合键…"
        onRecording?(true)
        // Capture before the app's Copy/Paste/Select All menu shortcuts consume command combinations.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, self.window?.isKeyWindow == true else { return event }
            self.keyDown(with: event)
            return nil
        }
        if let window {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.finish() })
            }
        }
    }
    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        recording = false
        title = shortcut?.display ?? "点击录制"
        onRecording?(false)
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        if event.keyCode == 51 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            onChange?(nil)
            finish()
            return
        }
        guard let shortcut = KeyboardShortcut.capture(event) else { title = "请包含 ⌘、⌥ 或 ⌃"; return }
        onChange?(shortcut)
        finish()
    }
}

struct ShortcutSettingsRow: View {
    let action: ShortcutAction
    @ObservedObject var preferences: Preferences
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(action.title)
                Spacer()
                ShortcutRecorder(shortcut: preferences.shortcut(action), onChange: { value in
                    do { try preferences.setShortcut(value, for: action); error = nil }
                    catch { self.error = error.localizedDescription }
                }, onRecording: { preferences.isRecordingShortcut = $0 }).frame(width: 155)
                Button { try? preferences.setShortcut(nil, for: action) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless).help("停用这个快捷键")
            }
            if let message = error ?? preferences.shortcutFailures[action.rawValue] {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
