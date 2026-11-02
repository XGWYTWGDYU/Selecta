import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "slider.horizontal.3") }
            translation.tabItem { Label("翻译服务", systemImage: "character.bubble") }
            ocr.tabItem { Label("离线 OCR", systemImage: "viewfinder") }
            PermissionsView().tabItem { Label("权限", systemImage: "lock.shield") }
            about.tabItem { Label("关于", systemImage: "info.circle") }
        }.padding(16).frame(width: 620, height: 540)
    }
    private var general: some View {
        Form {
            Section("启动与菜单栏") {
                LoginItemSettings()
                Toggle("隐藏菜单栏图标", isOn: $preferences.hideMenuBarIcon)
                Text("隐藏后可在翻译窗口点击设置按钮或按 ⌘, 打开设置；再次打开 Selecta 也能找回设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("自动语言切换") {
                Picker("首选目标语言", selection: $preferences.primary) { languageOptions }
                Picker("第二语言", selection: $preferences.secondary) { languageOptions }
                Text("原文与首选语言相同时，自动翻译为第二语言；其他语言翻译为首选语言。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("快捷键") {
                ForEach(ShortcutAction.allCases) { ShortcutSettingsRow(action: $0, preferences: preferences) }
                Text("点击录制后按下组合键。Esc 取消，删除键停用；修改后立即生效。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("恢复默认快捷键") { preferences.restoreShortcuts() }
            }
        }.formStyle(.grouped)
        .onChange(of: preferences.primary) { value in
            if value.sameBase(as: preferences.secondary) { preferences.secondary = value.sameBase(as: .en) ? .zhHans : .en }
        }
        .onChange(of: preferences.secondary) { value in
            if value.sameBase(as: preferences.primary) { preferences.secondary = preferences.primary.sameBase(as: .en) ? .zhHans : .en }
        }
    }
    private var languageOptions: some View {
        ForEach(Language.allCases.filter { $0 != .auto }) { Text($0.name).tag($0) }
    }
    private var translation: some View {
        Form {
            if !preferences.enabledProviders.isEmpty {
                Section("服务顺序") {
                    ServiceOrderList(preferences: preferences)
                }
            }
            ForEach([TranslationProvider.google, .deepL]) { serviceConfiguration($0) }
            ForEach(preferences.serviceOrder.filter(\.needsKey)) { serviceConfiguration($0) }
        }.formStyle(.grouped)
    }
    private func serviceConfiguration(_ provider: TranslationProvider) -> some View {
        Section(provider.rawValue) {
            Toggle("启用 \(provider.rawValue)", isOn: serviceBinding(provider, \.enabled))
            if provider.needsKey || provider == .deepL {
                CredentialField(account: provider.rawValue, title: provider == .deepL ? "API Key（可选，填写后使用官方接口）" : "API Key")
            }
            if provider.needsKey {
                TextField("API 地址（基础地址或完整接口均可）", text: serviceBinding(provider, \.endpoint))
                TextField("模型", text: serviceBinding(provider, \.model))
            }
            if provider == .google { TextField("Google 翻译地址", text: serviceBinding(provider, \.endpoint)) }
        }
    }
    private func serviceBinding<Value>(_ provider: TranslationProvider, _ path: WritableKeyPath<ServiceConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.configuration(provider)[keyPath: path] }, set: { value in
            var config = preferences.configuration(provider)
            config[keyPath: path] = value
            preferences.services[provider.rawValue] = config
        })
    }
    private var ocr: some View {
        Form {
            Section("识别引擎") {
                Text("百度 PaddleOCR · PP-OCRv5")
                Text("只使用本机 PaddleOCR 推理，不调用云端 OCR，也不切换其他引擎。截图翻译会将识别出的文字交给已启用的翻译服务；只 OCR 会复制文字并发送系统通知。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("百度 PaddleOCR · PP-OCRv5") {
                TextField("Python 可执行文件", text: $preferences.pythonPath)
                TextField("模型目录", text: $preferences.paddleModelPath)
                Text("Python 与模型保存在 Selecta 的应用数据目录中，可断网识别，无需百度 API Key。首次安装可运行 Scripts/setup-ocr.sh。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("应用数据") {
                Text(AppPaths.current.applicationSupport.path).font(.caption).textSelection(.enabled)
                Button("打开数据目录…") { NSWorkspace.shared.open(AppPaths.current.applicationSupport) }
            }
        }.formStyle(.grouped)
    }
    private var about: some View {
        VStack(spacing: 18) {
            Image(systemName: "character.bubble.fill").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Selecta").font(.largeTitle.bold())
            Text("专注于选词、截图和翻译。纯 Swift 的 macOS 客户端。")
            Text("基于 Easydict 的翻译协议与取词思路重写。\n遵循 GPL-3.0，保留原作者版权及许可证。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Link("Easydict · tisfeng / izual", destination: URL(string: "https://github.com/tisfeng/Easydict")!)
            Text("0.1.0").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CredentialField: View {
    let account: String
    let title: String
    @State private var value = ""
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SecureField(title, text: $value).onSubmit(save)
                Button("保存", action: save)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.onAppear { value = CredentialStore.read(account) }
    }
    private func save() {
        do { try CredentialStore.write(value.trimmingCharacters(in: .whitespacesAndNewlines), account: account); message = "已保存到钥匙串" }
        catch { message = error.localizedDescription }
    }
}
