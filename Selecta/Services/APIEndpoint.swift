import Foundation

enum APIEndpoint {
    static func chatCompletions(_ value: String) throws -> URL {
        let url = try HTTPClient.url(value.trimmingCharacters(in: .whitespacesAndNewlines))
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.path = "/" + path
            return components.url!
        }
        return url.appendingPathComponent("chat/completions")
    }
}
