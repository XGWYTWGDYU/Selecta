import Foundation
import Combine

/// Non-secret settings only. Credentials are stored separately in the macOS Keychain.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var primary: Language { didSet { save() } }
    @Published var secondary: Language { didSet { save() } }
    @Published var pythonPath: String { didSet { save() } }
    @Published var paddleModelPath: String { didSet { save() } }
    @Published var services: [String: ServiceConfiguration] { didSet { save() } }
    @Published var hideMenuBarIcon: Bool { didSet { save() } }
    @Published private(set) var serviceOrder: [TranslationProvider] { didSet { save() } }
    @Published private(set) var shortcuts: [String: KeyboardShortcut] { didSet { save() } }
    @Published var isRecordingShortcut = false
    @Published var shortcutFailures: [String: String] = [:]

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideMenuBarIcon = defaults.bool(forKey: "hideMenuBarIcon")
        let storedOrder = defaults.stringArray(forKey: "serviceOrder") ?? []
        var order: [TranslationProvider] = []
        for raw in storedOrder {
            if let provider = TranslationProvider(rawValue: raw), !order.contains(provider) { order.append(provider) }
        }
        serviceOrder = order + TranslationProvider.allCases.filter { !order.contains($0) }
        shortcuts = defaults.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: KeyboardShortcut].self, from: $0) } ?? KeyboardShortcut.defaults
        primary = Language(rawValue: defaults.string(forKey: "primary") ?? "") ?? .zhHans
        secondary = Language(rawValue: defaults.string(forKey: "secondary") ?? "") ?? .en
        defaults.removeObject(forKey: "ocrProvider")
        defaults.removeObject(forKey: "fallbackToVision")
        pythonPath = defaults.string(forKey: "pythonPath").flatMap { $0.isEmpty ? nil : $0 } ?? AppPaths.current.python.path
        paddleModelPath = defaults.string(forKey: "paddleModelPath").flatMap { $0.isEmpty ? nil : $0 } ?? AppPaths.current.models.path
        services = defaults.data(forKey: "services").flatMap { try? JSONDecoder().decode([String: ServiceConfiguration].self, from: $0) } ?? [:]
        for provider in TranslationProvider.allCases where services[provider.rawValue] == nil {
            services[provider.rawValue] = ServiceConfiguration(enabled: !provider.needsKey, endpoint: provider.defaultEndpoint, model: provider.defaultModel)
        }
        if var config = services[TranslationProvider.deepSeek.rawValue],
           URL(string: config.endpoint)?.host?.lowercased() == "api.deepseek.com",
           config.model == "deepseek-v4.1-flash" {
            config.model = "deepseek-flash"
            services[TranslationProvider.deepSeek.rawValue] = config
            save()
        }
    }
    func configuration(_ provider: TranslationProvider) -> ServiceConfiguration {
        services[provider.rawValue] ?? .init(endpoint: provider.defaultEndpoint, model: provider.defaultModel)
    }
    var enabledProviders: [TranslationProvider] { serviceOrder.filter { configuration($0).enabled } }
    func moveEnabledServices(from offsets: IndexSet, to destination: Int) {
        let enabled = enabledProviders
        guard !offsets.isEmpty, offsets.allSatisfy(enabled.indices.contains), (0...enabled.count).contains(destination) else { return }
        let moving = offsets.sorted().map { enabled[$0] }
        var reordered = enabled.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: insertion)
        var iterator = reordered.makeIterator()
        serviceOrder = serviceOrder.map { configuration($0).enabled ? iterator.next()! : $0 }
    }
    func shortcut(_ action: ShortcutAction) -> KeyboardShortcut? { shortcuts[action.rawValue] }
    func setShortcut(_ shortcut: KeyboardShortcut?, for action: ShortcutAction) throws {
        if let shortcut, let duplicate = ShortcutAction.allCases.first(where: { $0 != action && shortcuts[$0.rawValue]?.matches(shortcut) == true }) {
            throw SelectaError.message("这个快捷键已用于「\(duplicate.title)」。")
        }
        shortcuts[action.rawValue] = shortcut
    }
    func restoreShortcuts() { shortcuts = KeyboardShortcut.defaults }
    private func save() {
        defaults.set(hideMenuBarIcon, forKey: "hideMenuBarIcon")
        defaults.set(serviceOrder.map(\.rawValue), forKey: "serviceOrder")
        if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data, forKey: "shortcuts") }
        defaults.set(primary.rawValue, forKey: "primary")
        defaults.set(secondary.rawValue, forKey: "secondary")
        defaults.set(pythonPath, forKey: "pythonPath")
        defaults.set(paddleModelPath, forKey: "paddleModelPath")
        if let data = try? JSONEncoder().encode(services) { defaults.set(data, forKey: "services") }
    }
}
