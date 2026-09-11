import AppKit
import SwiftUI

/// SwiftUI owns the number. This narrow AppKit bridge owns only first-responder
/// routing and the insertion caret, so the first typed digit is never selected
/// and replaced by the second. The monitor is local to this app, not global.
struct DialNumberField: NSViewRepresentable {
    @Binding var text: String
    let onTone: (Character) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NumberTextField {
        let field = NumberTextField()
        field.isBezeled = false; field.drawsBackground = false
        field.isEditable = true; field.isSelectable = true
        field.focusRingType = .none; field.alignment = .center
        field.textColor = .labelColor
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .title2).pointSize, weight: .regular)
        field.placeholderString = L10n.text("Number or SIP Address")
        field.setAccessibilityLabel(L10n.text("Number or SIP Address"))
        field.setAccessibilityIdentifier("dial-number")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        context.coordinator.field = field
        field.windowChanged = { [weak coordinator = context.coordinator] attached in
            if attached { coordinator?.start() } else { coordinator?.stop() }
        }
        return field
    }
    func updateNSView(_ field: NumberTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }
    static func dismantleNSView(_ field: NumberTextField, coordinator: Coordinator) {
        coordinator.stop(); field.windowChanged = nil; field.delegate = nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NumberTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 280, height: 28)
    }

    final class NumberTextField: NSTextField {
        var windowChanged: ((Bool) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); windowChanged?(window != nil)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DialNumberField
        weak var field: NumberTextField?
        private var monitor: Any?
        private var menuTrackingDepth = 0
        init(_ parent: DialNumberField) { self.parent = parent }

        func start() {
            guard monitor == nil else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // AppKit invokes local event monitors on the main thread.
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handle(event) == nil
                }
                return consumed ? nil : event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil; menuTrackingDepth = 0
            NotificationCenter.default.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSMenu.didEndTrackingNotification, object: nil)
        }
        @objc private func menuBegan() { menuTrackingDepth += 1 }
        @objc private func menuEnded() { menuTrackingDepth = max(0, menuTrackingDepth - 1) }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let field, let window = field.window,
                  NSApp.isActive, NSApp.keyWindow === window, event.window === window,
                  window.attachedSheet == nil, NSApp.modalWindow == nil, menuTrackingDepth == 0,
                  let character = DialTypingPolicy.character(event.characters, modifiers: event.modifierFlags) else { return event }

            if let editor = field.currentEditor(), window.firstResponder === editor {
                parent.onTone(character)
                return event // Native editing, selection, undo and key repeat.
            }
            guard DialTypingPolicy.canRedirect(isOwnKeyWindow: true, hasSheetOrModal: false, menuTracking: false,
                                               responderAcceptsText: DialTypingPolicy.acceptsText(window.firstResponder)),
                  window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else { return event }
            // Append to an existing prepared number and leave the caret behind
            // the new digit. Consume the original event to avoid double input.
            Self.append(character, to: editor)
            parent.onTone(character)
            return nil
        }

        static func append(_ character: Character, to editor: NSTextView) {
            let end = NSRange(location: editor.string.utf16.count, length: 0)
            editor.setSelectedRange(end)
            editor.insertText(String(character), replacementRange: end)
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit(); return true
        }
    }
}
