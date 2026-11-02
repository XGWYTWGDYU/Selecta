import Foundation

struct HTTPClient {
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()
    var session: URLSession = privateSession

    static func url(_ value: String) throws -> URL {
        guard let url = URL(string: value), let host = url.host,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw SelectaError.message("服务地址必须是 HTTPS，或本机的 HTTP 地址。")
        }
        return url
    }
    func json(_ url: String, body: [String: Any]? = nil, headers: [String: String] = [:], timeout: TimeInterval = 45) async throws -> [String: Any] {
        var request = URLRequest(url: try Self.url(url), timeoutInterval: timeout)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await json(request)
    }
    func json(_ request: URLRequest) async throws -> [String: Any] {
        let data = try await data(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SelectaError.message("服务返回了无法解析的数据。")
        }
        return object
    }
    func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw SelectaError.message("没有收到有效的网络响应。") }
        guard (200..<300).contains(response.statusCode) else {
            // Do not include response bodies or request URLs: upstream errors can echo credentials/content.
            let hint: String
            switch response.statusCode {
            case 400: hint = "请求参数或模型名称不受支持，请核对服务提供商的模型 ID。"
            case 401: hint = "API Key 无效、已过期或未保存，请在设置中重新填写并保存。"
            case 402: hint = "账号余额或额度不足，请检查服务提供商账户。"
            case 403: hint = "账号没有调用权限，请检查模型访问权限。"
            case 404: hint = "接口路径或模型不存在，请核对 API 地址及模型 ID。"
            case 429: hint = "请求过于频繁或超过配额，请稍后重试。"
            default: hint = "请检查网络或稍后重试。"
            }
            throw SelectaError.message("服务请求失败（HTTP \(response.statusCode)）：\(hint)")
        }
        return data
    }
}
