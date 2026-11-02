import SwiftUI
import ServiceManagement

struct LoginItemSettings: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle("开机登录后自动启动 Selecta", isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: update))
            if status == .requiresApproval {
                Text("已添加登录项，等待在系统设置中允许。").font(.caption).foregroundStyle(.orange)
                Button("打开登录项设置…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in status = SMAppService.mainApp.status }
    }
    private func update(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = error.localizedDescription }
        status = SMAppService.mainApp.status
    }
}
