import XCTest
@testable import Selecta

final class LanguageRoutingTests: XCTestCase {
    func testChineseInputSwitchesToEnglishIncludingTraditionalChinese() {
        XCTAssertEqual(Language.target(source: .zhHans, primary: .zhHans, secondary: .en), .en)
        XCTAssertEqual(Language.target(source: .zhHant, primary: .zhHans, secondary: .en), .en)
    }
    func testOtherLanguagesUsePrimaryAndCustomPairWorks() {
        XCTAssertEqual(Language.target(source: .ja, primary: .zhHans, secondary: .en), .zhHans)
        XCTAssertEqual(Language.target(source: .fr, primary: .fr, secondary: .de), .de)
        XCTAssertEqual(Language.target(source: .auto, primary: .fr, secondary: .de), .fr)
    }
    func testProviderLanguageVariants() {
        XCTAssertEqual(Language.from(code: "zh-CN"), .zhHans)
        XCTAssertEqual(Language.from(code: "ZH-HANT"), .zhHant)
        XCTAssertEqual(Language.from(code: "en-US"), .en)
        XCTAssertNil(Language.from(code: "invalid"))
    }
    func testRealLanguageDetection() {
        XCTAssertEqual(Language.detect("This application translates selected text and recognizes images on your computer."), .en)
        XCTAssertTrue(Language.detect("这个程序可以识别图片中的文字，也可以翻译选中的句子。").isChinese)
    }
    @MainActor
    func testPreferencesSurviveRestartWithoutEnablingUnconfiguredAI() throws {
        let name = "SelectaTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Preferences(defaults: defaults)
        XCTAssertEqual(first.enabledProviders, [.google, .deepL])
        first.primary = .ja
        first.pythonPath = "/tmp/python"
        first.services[TranslationProvider.deepSeek.rawValue]?.enabled = true
        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.primary, .ja)
        XCTAssertEqual(second.pythonPath, "/tmp/python")
        XCTAssertEqual(second.enabledProviders, [.google, .deepL, .deepSeek])
    }
}
