import Foundation
import NaturalLanguage

enum Language: String, CaseIterable, Codable, Identifiable {
    case auto, zhHans = "zh-Hans", zhHant = "zh-Hant", en, ja, ko, fr, de, es, it, pt, ru, ar, nl, pl, uk, vi, th, id, ms, tr, sv, da, fi, el, cs, ro, hu, nb, bg, sk, sl, et, lv, lt, he, hi

    var id: String { rawValue }
    var name: String {
        if self == .auto { return "自动识别" }
        return Locale(identifier: "zh-Hans").localizedString(forIdentifier: rawValue) ?? rawValue
    }
    var googleCode: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .zhHant: return "zh-TW"
        default: return rawValue
        }
    }
    var isChinese: Bool { self == .zhHans || self == .zhHant }
    func sameBase(as other: Language) -> Bool {
        self == other || (isChinese && other.isChinese)
    }
    static func from(code: String) -> Language? {
        let code = code.lowercased()
        if code.hasPrefix("zh") { return code.contains("hant") || code.contains("tw") || code.contains("hk") ? .zhHant : .zhHans }
        return allCases.first { $0.rawValue.lowercased() == code } ?? allCases.first { $0.rawValue == code.components(separatedBy: "-")[0] }
    }
    static func detect(_ text: String) -> Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return from(code: recognizer.dominantLanguage?.rawValue ?? "") ?? .auto
    }
    static func target(source: Language, primary: Language, secondary: Language) -> Language {
        source.sameBase(as: primary) ? secondary : primary
    }
}

enum TranslationProvider: String, CaseIterable, Codable, Identifiable {
    case google = "Google", deepL = "DeepL", gemini = "Gemini", deepSeek = "DeepSeek", openAI = "OpenAI"
    var id: String { rawValue }
    var needsKey: Bool { self != .google && self != .deepL }
    var defaultEndpoint: String {
        switch self {
        case .google: return "https://translate.google.com"
        case .deepL: return "https://oneshot-free.www.deepl.com/v1/translate"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .openAI: return "https://api.openai.com/v1"
        }
    }
    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .deepSeek: return "deepseek-flash"
        case .openAI: return "gpt-4o-mini"
        default: return ""
        }
    }
}

struct Translation: Equatable {
    let text: String
    let detectedSource: Language?
}

struct ServiceConfiguration: Codable, Equatable {
    var enabled = false
    var endpoint: String
    var model: String
}

enum SelectaError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
