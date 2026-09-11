import AppKit
import SwiftUI
import Testing
@testable import TelefonX

@Suite struct ListSearchTests {
    @Test func persistentSearchTracksTextAndFocusRequests() {
        var state = ListSearchState()
        #expect(state.text.isEmpty)
        state.focus()
        let firstFocus = state.focusRequest
        state.text = "101"
        #expect(state.text == "101")
        state.clear()
        #expect(state.text.isEmpty)
        state.focus()
        #expect(state.focusRequest > firstFocus)
    }

    @Test func eachPrimarySectionRetainsAnIndependentSearch() {
        var states = SectionSearchStates()
        states[.contacts].text = "Müller"
        states[.favorites].text = "Alex"
        states[.history].text = "030"
        states[.reminders].text = "Angebot"

        #expect(states[.contacts].text == "Müller")
        #expect(states[.favorites].text == "Alex")
        #expect(states[.history].text == "030")
        #expect(states[.reminders].text == "Angebot")

        states[.contacts].clear()
        #expect(states[.contacts].text.isEmpty)
        #expect(states[.favorites].text == "Alex")
        #expect(states[.history].text == "030")
        #expect(states[.reminders].text == "Angebot")
    }

    @Test @MainActor func hiddenFieldIsDisabledAndDoesNotConsumeCommands() {
        _ = NSApplication.shared
        var query = "", cancels = 0, ends = 0
        let binding = Binding<String>(get: { query }, set: { query = $0 })
        let active = ListSearchField(text: binding, prompt: "Search", focusRequest: 0,
            onEndEditing: { ends += 1 }, onCancel: { cancels += 1 })
        let coordinator = active.makeCoordinator()
        let field = ListSearchField.makeField(coordinator: coordinator)
        coordinator.update(field, parent: active)
        let editor = NSTextView()
        #expect(field.isEnabled)
        #expect(field.placeholderString == "Search")
        query = "101"
        coordinator.update(field, parent: active)
        field.stringValue = ""
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(field.placeholderString == nil)
        #expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(cancels == 1)
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(ends == 1)
        var hidden = active; hidden.isActive = false
        coordinator.update(field, parent: hidden)
        #expect(!field.isEnabled)
        #expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(cancels == 1 && ends == 1)

        let compact = ListSearchField(text: binding, prompt: "Search Calls",
                                      visiblePrompt: "Search", focusRequest: 0)
        coordinator.update(field, parent: compact)
        #expect(field.placeholderString == "Search")
        #expect(field.accessibilityLabel() == "Search Calls")

        ListSearchField.dismantleNSView(field, coordinator: coordinator)
        #expect(field.delegate == nil)
    }
}
