import AppKit
import SwiftUI

/// Native multiline editing and undo with a SwiftUI-owned value.
struct NativeNotesEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.autohidesScrollers = true
        scrollView.focusRingType = .default

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 7)
        textView.setAccessibilityLabel(L10n.text("Notes"))
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
