import SwiftUI
import ApplicationServices
import UserNotifications
import Combine

@MainActor
final class PermissionsModel: ObservableObject {
    @Published var accessibility = false
    @Published var screenCapture = false
    @Published var notifications: UNAuthorizationStatus = .notDetermined
    @Published var message: String?
    func refresh() async {
        accessibility = AXIsProcessTrusted()
        screenCapture = CGPreflightScreenCaptureAccess()
        notifications = await NotificationService.shared.status()
    }
    func requestNotifications() async {
        do { _ = try await NotificationService.shared.requestAuthorization() }
        catch { message = error.localizedDescription }
        await refresh()
    }
    func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) }
    }
}

struct PermissionsView: View {
    @StateObject private var model = PermissionsModel()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        Form {
            Section {
                Text("权限只用于下列功能。此页面会自动刷新授权状态；从系统设置返回后，无需反复点击授权。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("辅助功能") {
                status(model.accessibility)
                Text("用于读取其他应用中选中的文字，以及取词失败时执行复制。没有此权限，选词翻译无法读取选区。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(model.accessibility ? "查看辅助功能设置…" : "前往授权辅助功能…") {
                    SelectionReader.requestPermission()
                    model.open("com.apple.preference.security?Privacy_Accessibility")
                }
            }
            Section("屏幕录制") {
                status(model.screenCapture)
                Text("用于读取你主动框选的截图，交给本地 OCR。请在系统设置中开启 Selecta；如果系统要求退出并重新打开，请按系统提示操作。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(model.screenCapture ? "查看屏幕录制设置…" : "前往授权屏幕录制…") {
                    model.open("com.apple.preference.security?Privacy_ScreenCapture")
                }
            }
            Section("系统通知") {
                status(model.notifications == .authorized || model.notifications == .provisional)
                Text("用于「只 OCR」完成后显示识别模型和识别全文。通知被系统关闭或专注模式屏蔽时，横幅可能不会出现，识别文字仍会复制到剪贴板。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.notifications == .notDetermined {
                    Button("允许 OCR 结果通知…") { Task { await model.requestNotifications() } }
                } else {
                    Button("打开通知设置…") { model.open("com.apple.Notifications-Settings.extension") }
                }
            }
            if let message = model.message { Text(message).foregroundStyle(.red) }
        }.formStyle(.grouped)
            .task { await model.refresh() }
            .onReceive(timer) { _ in Task { await model.refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refresh() } }
    }
    private func status(_ granted: Bool) -> some View {
        Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(granted ? .green : .orange)
    }
}
