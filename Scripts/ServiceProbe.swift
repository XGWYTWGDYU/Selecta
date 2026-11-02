import Foundation

/// Uses the production service implementation, without starting the GUI or reading real credentials.
@main
struct ServiceProbe {
    static func main() async {
        var failed = false
        for provider in [TranslationProvider.google, .deepL] {
            do {
                let result = try await TranslationService().translate("Hello, world!", from: .en, to: .zhHans, provider: provider, configuration: .init(endpoint: provider.defaultEndpoint, model: ""), key: "")
                print("\(provider.rawValue): \(result.text.isEmpty ? "FAILED" : "OK")")
            } catch {
                failed = true
                print("\(provider.rawValue): FAILED — \(error.localizedDescription)")
            }
        }
        if failed { exit(1) }
    }
}
