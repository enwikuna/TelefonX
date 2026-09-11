import AppKit

enum DialTypingPolicy {
    static func character(_ characters: String?, modifiers: NSEvent.ModifierFlags) -> Character? {
        guard modifiers.intersection([.command, .control, .option]).isEmpty,
              let characters, characters.count == 1, let character = characters.first,
              "0123456789*#+".contains(character) else { return nil }
        return character
    }

    static func acceptsText(_ responder: NSResponder?) -> Bool {
        // Includes AppKit's field editor, SwiftUI TextEditor, search and secure
        // fields. Never use class-name strings or assume all focus is ours.
        responder is NSText || responder is NSTextField
    }

    static func canRedirect(isOwnKeyWindow: Bool, hasSheetOrModal: Bool,
                            menuTracking: Bool, responderAcceptsText: Bool) -> Bool {
        isOwnKeyWindow && !hasSheetOrModal && !menuTracking && !responderAcceptsText
    }
}
