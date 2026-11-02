import AppKit
import Combine

enum TranslationState {
    case loading
    case success(String)
    case failure(String)
}

@MainActor
final class TranslationModel: ObservableObject {
    @Published var input = "" {
        didSet {
            if oldValue != input {
                translationTask?.cancel()
                results = [:]
            }
        }
    }
    @Published var source: Language = .auto
    @Published var target: Language = .auto
    @Published var detected: Language = .auto
    @Published var resolvedTarget: Language = .zhHans
    @Published var results: [TranslationProvider: TranslationState] = [:]
    @Published var ocrBusy = false
    @Published var notice: String?
    @Published var pinned = false
    @Published var popupWidth: CGFloat = 420
    @Published var collapsedProviders: Set<TranslationProvider> = []
    var onVisibility: ((Bool) -> Void)?
    var onOCRResult: ((OCRText) -> Void)?
    let preferences: Preferences
    private var translationTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?
    private var ocrGeneration = UUID()

    init(preferences: Preferences) { self.preferences = preferences }

    func translate(_ text: String? = nil) {
        if let text { input = text }
        translationTask?.cancel()
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        notice = nil
        detected = source == .auto ? Language.detect(query) : source
        let automaticTarget = target == .auto
        let primary = preferences.primary
        let secondary = preferences.secondary
        let destination = automaticTarget ? Language.target(source: detected, primary: primary, secondary: secondary) : target
        resolvedTarget = destination
        let from = source
        let services = preferences.enabledProviders.map { ($0, preferences.configuration($0), CredentialStore.read($0.rawValue)) }
        results = Dictionary(uniqueKeysWithValues: services.map { ($0.0, TranslationState.loading) })
        if services.isEmpty { notice = "请在设置中启用至少一个翻译服务。"; return }
        translationTask = Task {
            await withTaskGroup(of: (TranslationProvider, Result<Translation, Error>, Language).self) { group in
                for (provider, config, key) in services {
                    group.addTask {
                        do {
                            let service = TranslationService()
                            var actualTarget = destination
                            var result = try await service.translate(query, from: from, to: actualTarget, provider: provider, configuration: config, key: key)
                            // The provider can detect short/ambiguous text more reliably than NaturalLanguage.
                            if automaticTarget, from == .auto, let actualSource = result.detectedSource,
                               actualSource.sameBase(as: destination) {
                                actualTarget = Language.target(source: actualSource, primary: primary, secondary: secondary)
                                if actualTarget != destination {
                                    result = try await service.translate(query, from: actualSource, to: actualTarget, provider: provider, configuration: config, key: key)
                                }
                            }
                            return (provider, .success(result), actualTarget)
                        } catch { return (provider, .failure(error), destination) }
                    }
                }
                for await (provider, result, actualTarget) in group {
                    guard !Task.isCancelled else { continue }
                    switch result {
                    case .success(let result):
                        self.results[provider] = .success(result.text)
                        if from == .auto, let actualSource = result.detectedSource { self.detected = actualSource }
                        self.resolvedTarget = actualTarget
                    case .failure(let error): self.results[provider] = .failure(error.localizedDescription)
                    }
                }
            }
        }
    }

    func swap() {
        let previousSource = source == .auto ? detected : source
        source = target == .auto ? resolvedTarget : target
        target = previousSource == .auto ? preferences.secondary : previousSource
        translate()
    }

    func recognize(data: Data, copyOnly: Bool = false) {
        ocrTask?.cancel()
        let generation = UUID()
        ocrGeneration = generation
        let python = preferences.pythonPath
        let models = preferences.paddleModelPath
        ocrBusy = true
        notice = nil
        ocrTask = Task {
            defer { if self.ocrGeneration == generation { self.ocrBusy = false } }
            do {
                let result = try await PaddleOCR.recognize(data, python: python, models: models)
                try Task.checkCancellation()
                if copyOnly {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    self.onOCRResult?(result)
                } else {
                    self.input = result.text
                    self.translate()
                    self.notice = result.engine
                    self.onVisibility?(true)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.notice = error.localizedDescription
                self.onVisibility?(true)
            }
        }
    }

    func cancelOCR() {
        ocrTask?.cancel()
        ocrGeneration = UUID()
        ocrBusy = false
    }
}
