import AppKit
import SwiftUI

/// A native editable combo box: SwiftUI owns the value while AppKit provides
/// standard macOS completion and a disclosure list for existing group names.
struct GroupSuggestionField: NSViewRepresentable {
    @Binding var text: String
    let suggestions: [String]

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.delegate = context.coordinator
        comboBox.completes = true
        comboBox.isEditable = true
        comboBox.usesDataSource = false
        comboBox.numberOfVisibleItems = min(max(suggestions.count, 1), 8)
        comboBox.setAccessibilityLabel(L10n.text("Group"))
        configure(comboBox)
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self
        configure(comboBox)
    }

    private func configure(_ comboBox: NSComboBox) {
        let currentItems = comboBox.objectValues.compactMap { $0 as? String }
        if currentItems != suggestions {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: suggestions)
            comboBox.numberOfVisibleItems = min(max(suggestions.count, 1), 8)
        }
        if comboBox.currentEditor() == nil, comboBox.stringValue != text {
            comboBox.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: GroupSuggestionField

        init(parent: GroupSuggestionField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
        }
    }
}
