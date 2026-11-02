import XCTest
@testable import Selecta

private final class StubProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, [String: Any]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handle!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class HTTPRequestTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { session.invalidateAndCancel(); StubProtocol.handle = nil }

    func testProductionSessionDoesNotPersistCacheCookiesOrCredentials() {
        let configuration = HTTPClient().session.configuration
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testGoogleWorksWithoutKeyAndEncodesQuery() async throws {
        StubProtocol.handle = { request in
            let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(request.url?.path, "/translate_a/single")
            XCTAssertEqual(params.first { $0.name == "q" }?.value, "hello & 你好?")
            XCTAssertEqual(params.first { $0.name == "client" }?.value, "gtx")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, ["src": "en", "sentences": [["trans": "你好"]]])
        }
        let service = TranslationService(http: HTTPClient(session: session))
        let result = try await service.translate("hello & 你好?", from: .auto, to: .zhHans, provider: .google, configuration: .init(endpoint: TranslationProvider.google.defaultEndpoint, model: ""), key: "")
        XCTAssertEqual(result.text, "你好")
    }

    func testDeepLUsesFreeOfficialEndpointWithFXKey() async throws {
        StubProtocol.handle = { request in
            XCTAssertEqual(request.url?.host, "api-free.deepl.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key test:fx")
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertNil(body["source_lang"])
            XCTAssertEqual(body["target_lang"] as? String, "ZH-HANS")
            return (200, ["translations": [["text": "你好"]]])
        }
        let service = TranslationService(http: HTTPClient(session: session))
        _ = try await service.translate("hello", from: .auto, to: .zhHans, provider: .deepL, configuration: .init(endpoint: "", model: ""), key: "test:fx")
    }

    func testHTTPErrorDoesNotEchoCredentialOrContent() async throws {
        StubProtocol.handle = { _ in (429, ["error": "secret-key and private text"]) }
        do {
            _ = try await HTTPClient(session: session).json("https://example.com")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("429"))
            XCTAssertFalse(error.localizedDescription.contains("secret-key"))
        }
    }
}
