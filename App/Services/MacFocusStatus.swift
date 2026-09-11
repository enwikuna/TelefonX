import Intents
import Security

enum MacFocusAuthorization: Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized

    var label: String {
        switch self {
        case .notDetermined: L10n.text("Not Requested")
        case .restricted: L10n.text("Restricted")
        case .denied: L10n.text("Not Allowed")
        case .authorized: L10n.text("Allowed")
        }
    }
}

@MainActor enum MacFocusStatus {
    private static let communicationEntitlement = "com.apple.developer.usernotifications.communication" as CFString
    private static var center: INFocusStatusCenter { .default }

    static var isSupportedByCurrentSignature: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, communicationEntitlement, nil) else { return false }
        return CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((value as! CFBoolean))
    }

    static var authorization: MacFocusAuthorization {
        map(center.authorizationStatus)
    }

    static var isFocused: Bool? {
        guard isSupportedByCurrentSignature, authorization == .authorized else { return nil }
        return center.focusStatus.isFocused
    }

    static func requestAuthorization() async -> MacFocusAuthorization {
        await withCheckedContinuation { continuation in
            center.requestAuthorization { status in
                continuation.resume(returning: map(status))
            }
        }
    }

    nonisolated private static func map(_ status: INFocusStatusAuthorizationStatus) -> MacFocusAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }
}
