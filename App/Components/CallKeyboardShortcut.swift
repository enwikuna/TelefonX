import AppKit
import SwiftUI

enum CallShortcutAction: Equatable {
    case hold
    case mute
    case dtmf(Character)
}

enum CallShortcutPolicy {
    static func action(
        charactersIgnoringModifiers: String?,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool,
        responderAcceptsText: Bool
    ) -> CallShortcutAction? {
        guard !isRepeat, !responderAcceptsText,
              modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch charactersIgnoringModifiers?.lowercased() {
        case "h": return .hold
        case "m": return .mute
        default:
            guard let character = DialTypingPolicy.character(charactersIgnoringModifiers, modifiers: modifiers),
                  "0123456789*#".contains(character) else { return nil }
            return .dtmf(character)
        }
    }
}

/// A window-local bridge for unmodified call shortcuts. SwiftUI's
/// key-press routing depends on the current focus subtree, while this shortcut
/// must also work when a call control or the sidebar owns focus.
struct CallKeyboardShortcut: NSViewRepresentable {
    var enabled: Bool
    var dtmfEnabled: Bool
    let hold: () -> Void
    let mute: () -> Void
    let dtmf: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ShortcutView {
        let view = ShortcutView()
        context.coordinator.view = view
        view.windowChanged = { [weak coordinator = context.coordinator] attached in
            if attached { coordinator?.start() } else { coordinator?.stop() }
        }
        return view
    }
    func updateNSView(_ view: ShortcutView, context: Context) { context.coordinator.parent = self }
    static func dismantleNSView(_ view: ShortcutView, coordinator: Coordinator) {
        coordinator.stop()
        view.windowChanged = nil
    }

    final class ShortcutView: NSView {
        var windowChanged: ((Bool) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowChanged?(window != nil)
        }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: CallKeyboardShortcut
        weak var view: ShortcutView?
        private var monitor: Any?
        private var menuTrackingDepth = 0

        init(_ parent: CallKeyboardShortcut) { self.parent = parent }

        func start() {
            guard monitor == nil else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            menuTrackingDepth = 0
            NotificationCenter.default.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSMenu.didEndTrackingNotification, object: nil)
        }

        @objc private func menuBegan() { menuTrackingDepth += 1 }
        @objc private func menuEnded() { menuTrackingDepth = max(0, menuTrackingDepth - 1) }

        private func handle(_ event: NSEvent) -> Bool {
            guard parent.enabled, let window = view?.window,
                  NSApp.isActive, NSApp.keyWindow === window, event.window === window,
                  window.attachedSheet == nil, NSApp.modalWindow == nil, menuTrackingDepth == 0,
                  let action = CallShortcutPolicy.action(
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                    modifiers: event.modifierFlags,
                    isRepeat: event.isARepeat,
                    responderAcceptsText: DialTypingPolicy.acceptsText(window.firstResponder)
                  ) else { return false }
            switch action {
            case .hold: parent.hold()
            case .mute: parent.mute()
            case let .dtmf(character):
                guard parent.dtmfEnabled else { return false }
                parent.dtmf(String(character))
            }
            return true
        }
    }
}
