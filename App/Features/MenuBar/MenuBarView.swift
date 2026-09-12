import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.snapshot.accounts.isEmpty {
            statusRow(LineStatusPresentation.noAccounts)
        } else {
            ForEach(model.snapshot.accounts) { account in
                statusRow(LineStatusPresentation(
                    account: account,
                    state: model.registrations[account.id] ?? (account.enabled ? .offline : .disabled)
                ), locked: model.isAccountLockedByPro(account.id))
            }
        }
        Divider()
        Button("Open TelefonX", action: openMainWindow)
        if model.canSetDoNotDisturbManually {
            Menu("Do Not Disturb") {
                DoNotDisturbMenuItems()
            }
        } else {
            Toggle("Do Not Disturb", isOn: .constant(model.doNotDisturb)).disabled(true)
        }
        Divider()
        ForEach(model.presentedCalls) { call in
            Text(model.displayName(call.remote))
            if call.incoming && call.answeredAt == nil {
                Button("Answer") {
                    openMainWindow()
                    Task { await model.answer(call) }
                }
            }
            Button("Hang Up") { Task { await model.hangup(call) } }
        }
        if !model.presentedCalls.isEmpty {
            Divider()
        }
        Button("Settings …", action: openSettingsWindow)
        Button("Quit TelefonX") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func statusRow(_ status: LineStatusPresentation, locked: Bool = false) -> some View {
        Label {
            Text(status.title)
        } icon: {
            if locked {
                Image(systemName: "lock.fill")
            } else {
                Image(nsImage: MenuStatusDot.image(for: status.level))
                    .renderingMode(.original)
            }
        }
        .accessibilityLabel(locked
            ? L10n.format("Line Status: %@, Locked · TelefonX Pro", status.accessibilityTitle)
            : L10n.format("Line Status: %@", status.accessibilityTitle))
    }
}

private enum MenuStatusDot {
    static func image(for level: LineStatusLevel) -> NSImage {
        let color: NSColor = switch level {
        case .connected: .systemGreen
        case .connecting: .systemOrange
        case .unavailable: .systemRed
        case .inactive: .secondaryLabelColor
        }
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { bounds in
            color.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
