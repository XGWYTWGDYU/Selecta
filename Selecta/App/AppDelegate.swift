import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences: Preferences
    private lazy var model = TranslationModel(preferences: preferences)
    private let hotkeys = Hotkeys()
    private var statusItem: NSStatusItem?
    private var panel: TranslationPanel?
    private var settingsWindow: NSWindow?
    private var dismissMonitors: [Any] = []
    private var sourceObservation: NSObjectProtocol?
    private var sourceApplication: NSRunningApplication?
    private var shortcutsObservation: AnyCancellable?
    private var layoutObservation: AnyCancellable?
    private var menuVisibilityObservation: AnyCancellable?
    private var captureTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?

    override init() {
        preferences = .shared
        super.init()
    }
    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as a host, without registering global shortcuts or showing windows.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        sourceApplication = NSWorkspace.shared.frontmostApplication
        sourceObservation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.sourceApplication = app }
        }
        do { try AppPaths.current.prepare() }
        catch { model.notice = "无法创建 Selecta 数据目录：\(error.localizedDescription)" }
        createMenu()
        NotificationService.shared.configure()
        model.onVisibility = { [weak self] show in if show { self?.showPanel() } }
        model.onOCRResult = { [weak self] result in
            Task { @MainActor in
                do { try await NotificationService.shared.postOCR(result) }
                catch { self?.model.notice = error.localizedDescription; self?.showPanel() }
            }
        }
        menuVisibilityObservation = preferences.$hideMenuBarIcon.receive(on: RunLoop.main).sink { [weak self] hidden in
            self?.statusItem?.isVisible = !hidden
        }
        hotkeys.onAction = { [weak self] id in
            switch id {
            case 1: self?.showPanel(at: NSEvent.mouseLocation)
            case 2: self?.translateSelection()
            case 3: self?.screenshot()
            case 4: self?.screenshot(copyOnly: true)
            default: break
            }
        }
        shortcutsObservation = Publishers.CombineLatest(preferences.$shortcuts, preferences.$isRecordingShortcut)
            .receive(on: RunLoop.main)
            .sink { [weak self] shortcuts, recording in
                guard let self else { return }
                self.preferences.shortcutFailures = self.hotkeys.register(shortcuts, paused: recording)
                self.createMenu()
            }
    }
    func applicationWillTerminate(_ notification: Notification) {
        PaddleWorker.shared.shutdown()
        hotkeys.stop()
        dismissMonitors.forEach(NSEvent.removeMonitor)
        if let sourceObservation { NSWorkspace.shared.notificationCenter.removeObserver(sourceObservation) }
        captureTask?.cancel()
        selectionTask?.cancel()
        model.cancelOCR()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if preferences.hideMenuBarIcon { showSettings(); return true }
        return false
    }
    private func createMenu() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Selecta")
        let menu = NSMenu()
        for (shortcutAction, action) in [(ShortcutAction.input, #selector(openInput)), (.selection, #selector(openSelection)), (.screenshot, #selector(openScreenshot)), (.copyOCR, #selector(copyScreenshot))] {
            let title = shortcutAction.title + (preferences.shortcut(shortcutAction).map { "  " + $0.display } ?? "")
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        if !preferences.shortcutFailures.isEmpty {
            let warning = NSMenuItem(title: "快捷键冲突，前往设置…", action: #selector(showSettings), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "退出 Selecta", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        item.isVisible = !preferences.hideMenuBarIcon
        statusItem = item
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = menu.copy() as? NSMenu
        main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    private func createPanel() {
        let window = TranslationPanel()
        panel = window
        window.title = "Selecta"
        window.delegate = self
        let hosting = NSHostingView(rootView: TranslationView(model: model, preferences: preferences, onSettings: { [weak self] in self?.showSettings() }, onSearch: { [weak self] in self?.searchInput() }))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        window.contentView = hosting
        window.center()
        layoutObservation = model.objectWillChange.merge(with: preferences.objectWillChange)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main).sink { [weak self] in self?.resizePopup() }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.dismissPopupIfUnpinned()
        }) { dismissMonitors.append(monitor) }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.panel { self?.dismissPopupIfUnpinned() }
            return event
        }
        if let local { dismissMonitors.append(local) }
        let settingsKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            if window?.isKeyWindow == true, modifiers == .command, event.keyCode == 43 {
                self?.showSettings()
                return nil
            }
            return event
        }
        if let settingsKey { dismissMonitors.append(settingsKey) }
    }
    private func dismissPopupIfUnpinned() {
        if !model.pinned { panel?.orderOut(nil) }
    }
    private func showPanel(at anchor: NSPoint? = nil, activate: Bool = true) {
        if panel == nil { createPanel() }
        guard let panel else { return }
        let location = anchor ?? (panel.isVisible ? NSPoint(x: panel.frame.midX, y: panel.frame.midY) : NSEvent.mouseLocation)
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        resizePopup(in: bounds)
        panel.present(at: anchor ?? (panel.isVisible ? nil : location), in: bounds, activate: activate)
        if activate, let editor = findEditor(panel.contentView) { panel.makeFirstResponder(editor) }
    }
    private func findEditor(_ view: NSView?) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        for child in view?.subviews ?? [] { if let editor = findEditor(child) { return editor } }
        return nil
    }
    private func resizePopup(in visibleFrame: NSRect? = nil) {
        guard let panel else { return }
        let bounds = visibleFrame ?? (panel.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleResults = model.results.filter { preferences.configuration($0.key).enabled }
        let contentHeight = PopupLayout.contentHeight(input: model.input, notice: model.notice, results: visibleResults, collapsed: model.collapsedProviders, width: panel.frame.width)
        let height = min(bounds.height * 0.75, max(165, ceil(contentHeight)))
        guard abs(panel.frame.height - height) > 1 else { return }
        panel.setFrame(PopupPlacement.frame(size: NSSize(width: panel.frame.width, height: height), anchor: panel.placementAnchor, current: panel.frame, visibleFrame: bounds), display: true)
    }
    func windowDidResize(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        if model.popupWidth != panel.frame.width { model.popupWidth = panel.frame.width }
    }
    private func translateSelection() {
        let anchor = NSEvent.mouseLocation
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? sourceApplication : frontmost
        selectionTask?.cancel()
        model.cancelOCR()
        model.input = ""
        guard AXIsProcessTrusted() else {
            SelectionReader.requestPermission()
            model.notice = "选词翻译需要辅助功能权限。授权后请再次触发选词翻译。"
            showPanel(at: anchor)
            return
        }
        model.notice = "正在读取选中文字…"
        selectionTask = Task {
            if let source, NSWorkspace.shared.frontmostApplication?.processIdentifier != source.processIdentifier {
                source.activate(options: [.activateIgnoringOtherApps])
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled else { return }
            showPanel(at: anchor, activate: false)
            let text = await SelectionReader.read(from: source, allowCopy: true)
            guard !Task.isCancelled else { return }
            if let text { model.translate(text) } else { model.notice = "未能读取选中文字。请确认选区，或使用截图翻译。" }
            showPanel(at: anchor)
        }
    }
    private func screenshot(copyOnly: Bool = false) {
        guard captureTask == nil else { return }
        selectionTask?.cancel()
        model.cancelOCR()
        panel?.orderOut(nil)
        captureTask = Task {
            defer { captureTask = nil }
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                if let data = try await ScreenCapture.capture() {
                    if !copyOnly { model.input = ""; model.detected = .auto }
                    model.recognize(data: data, copyOnly: copyOnly)
                    if !copyOnly { showPanel(at: NSEvent.mouseLocation) }
                }
            } catch {
                guard !Task.isCancelled else { return }
                model.notice = error.localizedDescription
                showPanel(at: NSEvent.mouseLocation)
            }
        }
    }
    private func searchInput() {
        if let url = GoogleSearch.url(for: model.input) { NSWorkspace.shared.open(url) }
    }
    @objc private func showSettings() {
        panel?.orderOut(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 652, height: 572), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Selecta 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func openInput() { showPanel(at: NSEvent.mouseLocation) }
    @objc private func openSelection() { translateSelection() }
    @objc private func openScreenshot() { screenshot() }
    @objc private func copyScreenshot() { screenshot(copyOnly: true) }
}
