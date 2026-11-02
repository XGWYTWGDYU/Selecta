import AppKit

enum PopupLayout {
    static func inputHeight(_ text: String, width: CGFloat) -> CGFloat {
        min(75, max(54, textHeight(text, width: width - 22, font: 14) + 16))
    }
    static func contentHeight(input: String, notice: String?, results: [TranslationProvider: TranslationState], collapsed: Set<TranslationProvider>, width: CGFloat) -> CGFloat {
        var height = 28 + inputHeight(input, width: width - 20) + 24 + 35 + 7 + 7
        if let notice {
            height += max(14, textHeight(notice, width: width - 50, font: 11)) + 10 + 7
        }
        for (provider, state) in results {
            height += 28 + 7
            if !collapsed.contains(provider) {
                let text: String
                switch state {
                case .loading: text = "翻译中…"
                case .success(let result): text = result
                case .failure(let error): text = error
                }
                height += textHeight(text, width: width - 40, font: 14, lineSpacing: 3) + 24
            }
        }
        return max(165, ceil(height))
    }
    private static func textHeight(_ text: String, width: CGFloat, font: CGFloat, lineSpacing: CGFloat = 0) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let rect = (text as NSString).boundingRect(with: NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: font), .paragraphStyle: style])
        return ceil(rect.height)
    }
}
