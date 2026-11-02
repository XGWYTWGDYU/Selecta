import Foundation

enum GoogleSearch {
    static func url(for input: String) -> URL? {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var url = URLComponents(string: "https://www.google.com/search")!
        url.queryItems = [URLQueryItem(name: "q", value: input)]
        return url.url
    }
}
