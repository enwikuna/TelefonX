import SwiftUI
import TelefonDomain

struct RegistrationIndicator: View {
    let state: RegistrationState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityLabel(label)
            .help(label)
    }

    var label: String {
        switch state {
        case .registered:
            L10n.text("Connected")
        case .registering:
            L10n.text("Connecting …")
        case .failed(let code):
            L10n.format("Disconnected (%lld)", Int64(code))
        case .disabled:
            L10n.text("Disabled")
        case .offline:
            L10n.text("Offline")
        }
    }

    private var color: Color {
        switch state {
        case .registered:
            TelephonyColors.connected
        case .registering:
            TelephonyColors.pending
        case .failed:
            TelephonyColors.failed
        case .disabled, .offline:
            .secondary
        }
    }
}
