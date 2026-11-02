import XCTest
@testable import Selecta

final class ServiceAndNotificationTests: XCTestCase {
    func testChatEndpointAcceptsBaseAndCompleteURLs() throws {
        for input in ["https://api.deepseek.com/v1", "https://api.deepseek.com/v1/", "https://api.deepseek.com/v1/chat/completions", "https://api.deepseek.com/v1/chat/completions/"] {
            XCTAssertEqual(try APIEndpoint.chatCompletions(input).path, "/v1/chat/completions")
        }
        XCTAssertEqual(try APIEndpoint.chatCompletions("https://api.deepseek.com").path, "/chat/completions")
    }
    func testSearchEncodesOriginalUnicodeAndLineBreaks() throws {
        let original = "原文 & words?\nsecond line"
        let url = try XCTUnwrap(GoogleSearch.url(for: original))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertEqual(components.queryItems?.first?.value, original)
        XCTAssertNil(GoogleSearch.url(for: " \n "))
    }
    @MainActor
    func testOCRNotificationContainsModelAndCompleteOriginalResult() {
        let text = "第一行\nSecond line. " + String(repeating: "识别内容", count: 100)
        let content = NotificationService.content(for: OCRText(text: text, engine: "PaddleOCR · PP-OCRv5"))
        XCTAssertEqual(content.title, "PaddleOCR · PP-OCRv5 OCR结果")
        XCTAssertEqual(content.body, text)
    }
    @MainActor
    func testServiceOrderNormalizesAndPersistsAndKeepsEnabledOrder() throws {
        let name = "SelectaServiceOrder-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["DeepSeek", "DeepSeek", "unknown", "Google"], forKey: "serviceOrder")
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.serviceOrder, [.deepSeek, .google, .deepL, .gemini, .openAI])
        preferences.services["DeepSeek"]?.enabled = true
        XCTAssertEqual(preferences.enabledProviders, [.deepSeek, .google, .deepL])
        preferences.moveEnabledServices(from: IndexSet(integer: 2), to: 1)
        XCTAssertEqual(Preferences(defaults: defaults).serviceOrder, [.deepSeek, .deepL, .google, .gemini, .openAI])
    }
    @MainActor
    func testDisabledServicesAreExcludedAndKeepTheirSavedSlotsDuringDrag() throws {
        let name = "SelectaEnabledOrder-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        prefs.services["DeepSeek"]?.enabled = true
        prefs.services["Google"]?.enabled = false
        XCTAssertEqual(prefs.enabledProviders, [.deepL, .deepSeek])
        prefs.moveEnabledServices(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(prefs.enabledProviders, [.deepSeek, .deepL])
        XCTAssertEqual(prefs.serviceOrder, [.google, .deepSeek, .gemini, .deepL, .openAI])
        prefs.services["DeepL"]?.enabled = false
        XCTAssertEqual(prefs.enabledProviders, [.deepSeek])
        prefs.services["Google"]?.enabled = true
        XCTAssertEqual(prefs.enabledProviders, [.google, .deepSeek])
        XCTAssertEqual(Preferences(defaults: defaults).enabledProviders, prefs.enabledProviders)
    }
    @MainActor
    func testDraggingDownwardAndMovingMultipleEnabledRows() throws {
        let name = "SelectaMultiDrag-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        prefs.services["DeepSeek"]?.enabled = true
        prefs.moveEnabledServices(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(prefs.enabledProviders, [.deepL, .deepSeek, .google])
        prefs.moveEnabledServices(from: IndexSet([0, 1]), to: 3)
        XCTAssertEqual(prefs.enabledProviders, [.google, .deepL, .deepSeek])
    }
    @MainActor
    func testOfficialDeepSeekModelMigrationPreservesEndpoint() throws {
        let name = "SelectaDeepSeekMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let endpoint = "https://api.deepseek.com/v1/chat/completions"
        defaults.set(try JSONEncoder().encode(["DeepSeek": ServiceConfiguration(enabled: true, endpoint: endpoint, model: "deepseek-v4.1-flash")]), forKey: "services")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.configuration(.deepSeek).model, "deepseek-flash")
        XCTAssertEqual(prefs.configuration(.deepSeek).endpoint, endpoint)
        XCTAssertTrue(prefs.configuration(.deepSeek).enabled)
    }
}
