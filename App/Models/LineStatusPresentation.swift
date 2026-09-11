import Foundation
import TelefonDomain

enum LineStatusLevel: Equatable {
    case connected
    case connecting
    case unavailable
    case inactive
}

struct LineStatusPresentation: Equatable {
    let title: String
    let accessibilityTitle: String
    let level: LineStatusLevel

    static var noAccounts: LineStatusPresentation { LineStatusPresentation(title: L10n.text("No Line Configured"),
                                                    accessibilityTitle: L10n.text("No Line Configured"),
                                                    level: .inactive)
    }

    init(account: PhoneAccount, state: RegistrationState) {
        let name = account.name.isEmpty ? L10n.text("Unnamed Line") : account.name
        let status: String
        switch state {
        case .registered:
            status = L10n.text("Connected"); level = .connected
        case .registering:
            status = L10n.text("Connecting …"); level = .connecting
        case .failed:
            status = L10n.text("Disconnected"); level = .unavailable
        case .disabled:
            status = L10n.text("Disabled"); level = .inactive
        case .offline:
            status = L10n.text("Offline"); level = .unavailable
        }
        title = Self.menuTitle(name)
        accessibilityTitle = "\(name), \(status)"
    }

    private init(title: String, accessibilityTitle: String, level: LineStatusLevel) {
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.level = level
    }

    private static func menuTitle(_ name: String) -> String {
        name.count <= 30 ? name : String(name.prefix(29)) + "…"
    }
}
