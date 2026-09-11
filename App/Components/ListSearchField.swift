import AppKit
import SwiftUI

/// A real NSSearchField, owned by the list's toolbar rather than the window's
/// automatically trailing searchable item. SwiftUI owns the query and focus request.
struct ListSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    var visiblePrompt: String? = nil
    let focusRequest: Int
    var isActive = true
    var onEndEditing: () -> Void = {}
    var onCancel: () -> Void = {}
    private var displayedPrompt: String { L10n.text(visiblePrompt ?? prompt) }
    private var localizedPrompt: String { L10n.text(prompt) }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSSearchField {
        Self.makeField(coordinator: context.coordinator)
    }
    static func makeField(coordinator: Coordinator) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.controlSize = .large
        field.setAccessibilityIdentifier("list-search")
        return field
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? ListSearchToolbarPresentation.fieldWidth,
               height: proposal.height ?? nsView.intrinsicContentSize.height)
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.update(field, parent: self)
    }
    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) { field.delegate = nil }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ListSearchField
        var lastFocusRequest: Int
        private var lastPrompt: String
        private var suppressesPlaceholder = false
        init(parent: ListSearchField) {
            self.parent = parent
            lastFocusRequest = parent.focusRequest
            lastPrompt = parent.displayedPrompt
        }
        func update(_ field: NSSearchField, parent: ListSearchField) {
            self.parent = parent
            field.isEnabled = parent.isActive
            if field.stringValue != parent.text { field.stringValue = parent.text }
            if parent.displayedPrompt != lastPrompt {
                lastPrompt = parent.displayedPrompt
                suppressesPlaceholder = false
            } else if !parent.isActive {
                suppressesPlaceholder = false
            } else if lastFocusRequest != parent.focusRequest {
                suppressesPlaceholder = false
            }
            field.placeholderString = parent.isActive && !suppressesPlaceholder ? parent.displayedPrompt : nil
            field.setAccessibilityLabel(parent.localizedPrompt)
            if !parent.isActive, field.currentEditor() != nil { field.window?.makeFirstResponder(nil) }
            if parent.isActive, lastFocusRequest != parent.focusRequest, let window = field.window {
                lastFocusRequest = parent.focusRequest
                window.makeFirstResponder(field)
            }
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            if !parent.text.isEmpty, field.stringValue.isEmpty {
                // Avoid a one-frame placeholder flash while the bound query catches up.
                suppressesPlaceholder = true
                field.placeholderString = nil
            } else if !field.stringValue.isEmpty {
                suppressesPlaceholder = false
            }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isActive { parent.onEndEditing() }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.isActive, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            parent.onCancel()
            return true
        }
    }
}

struct ListSearchFocusKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var focusListSearch: (() -> Void)? {
        get { self[ListSearchFocusKey.self] }
        set { self[ListSearchFocusKey.self] = newValue }
    }
}

struct ListSearchCommands: Commands {
    @FocusedValue(\.focusListSearch) private var focusSearch
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Search List") { focusSearch?() }
                .keyboardShortcut("f", modifiers: .command).disabled(focusSearch == nil)
        }
    }
}
