import AppKit
import SwiftUI

struct QueryEditor: NSViewRepresentable {
    @Binding var text: String
    var onTranslate: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 120))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let editor = SubmitTextView(frame: scroll.contentView.bounds)
        editor.minSize = NSSize(width: 0, height: 54)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 6, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.onTranslate = onTranslate
        editor.setAccessibilityLabel("待翻译原文，回车翻译，Shift 回车换行")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? SubmitTextView else { return }
        context.coordinator.parent = self
        editor.onTranslate = onTranslate
        if editor.string != text { editor.string = text }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QueryEditor
        init(_ parent: QueryEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private final class SubmitTextView: NSTextView {
    var onTranslate: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        // Respect marked text so Return confirms IME composition before submitting Chinese/Japanese input.
        if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onTranslate?()
        } else { super.keyDown(with: event) }
    }
}
