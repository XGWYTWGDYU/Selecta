import XCTest
@testable import Selecta

final class TranslationServiceTests: XCTestCase {
    func testGoogleJoinsSegmentsWithoutLosingLineBreaks() throws {
        let result = try TranslationService.parseGoogle(["src": "en", "sentences": [["trans": "你好。\n"], ["trans": "世界。"]]])
        XCTAssertEqual(result, Translation(text: "你好。\n世界。", detectedSource: .en))
    }
    func testDeepLOfficialAndOneshotSharedResponse() throws {
        let result = try TranslationService.parseDeepL(["translations": [["text": "Hello", "detected_source_language": "ZH"]]])
        XCTAssertEqual(result.text, "Hello")
        XCTAssertEqual(result.detectedSource, .zhHans)
    }
    func testEmptyOrBlockedResponsesAreErrors() {
        XCTAssertThrowsError(try TranslationService.parseDeepL(["translations": []]))
        XCTAssertThrowsError(try TranslationService.parseGoogle(["sentences": [["trans": "   "]]]))
        XCTAssertThrowsError(try TranslationService.parseGemini(["promptFeedback": ["blockReason": "SAFETY"]]))
        XCTAssertThrowsError(try TranslationService.parseChat(["choices": [["message": ["content": NSNull()]]]]))
    }
    func testGeminiDoesNotDisplayThoughtParts() throws {
        let result = try TranslationService.parseGemini(["candidates": [["content": ["parts": [["text": "private reasoning", "thought": true], ["text": "Bonjour"]]]]]])
        XCTAssertEqual(result.text, "Bonjour")
    }
    func testOpenAIAndDeepSeekParseContent() throws {
        XCTAssertEqual(try TranslationService.parseChat(["choices": [["message": ["content": "你好"]]]]).text, "你好")
    }
    func testEndpointsRequireTLSExceptLoopback() throws {
        XCTAssertNoThrow(try HTTPClient.url("http://127.0.0.1:1234/v1"))
        XCTAssertNoThrow(try HTTPClient.url("https://api.example.com/v1"))
        XCTAssertThrowsError(try HTTPClient.url("http://api.example.com/v1"))
        XCTAssertThrowsError(try HTTPClient.url("file:///tmp/api"))
    }
}
