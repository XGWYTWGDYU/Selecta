import SwiftUI

struct OCRSetupView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject private var installer = OCRInstaller.shared

    var body: some View {
        Section("OCR 环境与模型") {
            HStack(alignment: .top, spacing: 10) {
                if installer.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: installer.failed ? "exclamationmark.circle" : installer.ready ? "checkmark.circle.fill" : "arrow.down.circle").foregroundStyle(installer.ready ? .green : .secondary) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(installer.message).textSelection(.enabled)
                    if installer.busy && installer.step > 0 {
                        Text("步骤 \(installer.step)/5 · 首次下载可能需要几分钟").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button(installer.ready ? "重新安装 OCR" : installer.failed ? "重试安装" : "下载并安装 OCR") { installer.install(preferences: preferences) }
                    .disabled(installer.busy)
                if installer.busy { Button("取消") { installer.cancel() } }
                else { Button("检查环境") { installer.check(preferences: preferences) } }
            }
            Text("首次安装需要联网，自动下载 Python、依赖与百度 PP-OCRv5 模型。安装完成后可离线识别，无需终端或其他工具。")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("高级设置") {
                TextField("Python 可执行文件", text: $preferences.pythonPath)
                TextField("模型目录", text: $preferences.paddleModelPath)
            }.disabled(installer.busy)
        }
        .task { installer.check(preferences: preferences) }
    }
}
