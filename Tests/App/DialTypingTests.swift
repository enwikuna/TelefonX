import AppKit
import Testing
@testable import TelefonX

@Suite @MainActor struct DialTypingTests {
    @Test(arguments: Array("0123456789*#+"))
    func recognizesNumberRowAndKeypad(_ character: Character) {
        #expect(DialTypingPolicy.character(String(character), modifiers: []) == character)
        #expect(DialTypingPolicy.character(String(character), modifiers: [.numericPad]) == character)
        #expect(DialTypingPolicy.character(String(character), modifiers: [.shift]) == character)
    }
    @Test func preservesShortcutsAndNonDialInput() {
        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option, [.shift, .command], [.numericPad, .command]] {
            #expect(DialTypingPolicy.character("1", modifiers: modifiers) == nil)
        }
        for input in ["", "12", "a", "ä", "١", "\r", "\t", " ", "\u{7f}"] {
            #expect(DialTypingPolicy.character(input, modifiers: []) == nil)
        }
        #expect(DialTypingPolicy.character(nil, modifiers: []) == nil)
    }
    @Test func searchSecureFieldsAndTextEditorsKeepFocus() {
        for responder: NSResponder in [NSTextView(), NSTextField(), NSSearchField(), NSSecureTextField()] {
            #expect(DialTypingPolicy.acceptsText(responder))
        }
        #expect(!DialTypingPolicy.acceptsText(NSView()))
        #expect(!DialTypingPolicy.acceptsText(NSButton()))
        #expect(!DialTypingPolicy.acceptsText(nil))
    }
    @Test func onlyUnoccupiedMainWindowInputCanRedirect() {
        for ownWindow in [true, false] {
            for dialog in [true, false] {
                for menu in [true, false] {
                    for editing in [true, false] {
                        #expect(DialTypingPolicy.canRedirect(isOwnKeyWindow: ownWindow, hasSheetOrModal: dialog,
                                                            menuTracking: menu, responderAcceptsText: editing)
                                == (ownWindow && !dialog && !menu && !editing))
                    }
                }
            }
        }
    }
    @Test func firstDigitIsAppendedExactlyOnceAndCaretFollowsIt() {
        let editor = NSTextView()
        editor.string = "12"
        editor.setSelectedRange(NSRange(location: 0, length: 2)) // Typical selection on focus.
        DialNumberField.Coordinator.append("3", to: editor)
        #expect(editor.string == "123")
        #expect(editor.selectedRange() == NSRange(location: 3, length: 0))
        editor.insertText("4", replacementRange: editor.selectedRange())
        #expect(editor.string == "1234")
        #expect(editor.selectedRange() == NSRange(location: 4, length: 0))
    }

    @Test func callShortcutsUsePlainKeysOnlyOutsideTextEditing() {
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "h", modifiers: [], isRepeat: false, responderAcceptsText: false
        ) == .hold)
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "H", modifiers: [.shift], isRepeat: false, responderAcceptsText: false
        ) == .hold)
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "m", modifiers: [], isRepeat: false, responderAcceptsText: false
        ) == .mute)
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "M", modifiers: [.shift], isRepeat: false, responderAcceptsText: false
        ) == .mute)
        for character: Character in "0123456789*#" {
            #expect(CallShortcutPolicy.action(
                charactersIgnoringModifiers: String(character), modifiers: [], isRepeat: false, responderAcceptsText: false
            ) == .dtmf(character))
        }
        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option] {
            #expect(CallShortcutPolicy.action(
                charactersIgnoringModifiers: "h", modifiers: modifiers, isRepeat: false, responderAcceptsText: false
            ) == nil)
            #expect(CallShortcutPolicy.action(
                charactersIgnoringModifiers: "m", modifiers: modifiers, isRepeat: false, responderAcceptsText: false
            ) == nil)
        }
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "h", modifiers: [], isRepeat: true, responderAcceptsText: false
        ) == nil)
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "m", modifiers: [], isRepeat: false, responderAcceptsText: true
        ) == nil)
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "+", modifiers: [], isRepeat: false, responderAcceptsText: false
        ) == nil)
        #expect(CallShortcutPolicy.action(
            charactersIgnoringModifiers: "x", modifiers: [], isRepeat: false, responderAcceptsText: false
        ) == nil)
    }
}
