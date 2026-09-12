import Foundation

enum AppError: LocalizedError, Equatable {
    case storageUnavailable
    case microphoneDenied
    case unavailableDevice(String)
    case noLine
    case lineUnavailable
    case callInProgress
    case conferenceInProgress
    case missingPassword
    case unsupportedSTUN
    case reminderDateInPast
    case focusStatusUnavailable
    case focusStatusCapabilityMissing

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            L10n.text("The local data store is unavailable. Quit the app and export diagnostics.")
        case .microphoneDenied:
            L10n.text("Microphone access is missing. Allow it in System Settings → Privacy & Security → Microphone.")
        case .unavailableDevice(let name):
            L10n.format("The selected audio device is not connected: %@. Choose another device in Audio Settings.", name)
        case .noLine:
            L10n.text("Select a registered line first.")
        case .lineUnavailable:
            L10n.text("The line is no longer reachable. Check your VPN or network connection.")
        case .callInProgress:
            L10n.text("End active calls first.")
        case .conferenceInProgress:
            L10n.text("End the active conference first.")
        case .missingPassword:
            L10n.text("Enter the SIP password for this line. It is stored only in the macOS Keychain.")
        case .unsupportedSTUN:
            L10n.text("TelefonX does not currently support custom STUN servers. Check the network requirements of your SIP provider or phone system.")
        case .reminderDateInPast:
            L10n.text("Choose a time in the future before reopening or saving the callback.")
        case .focusStatusUnavailable:
            L10n.text("The macOS Focus status is unavailable. In System Settings → Focus → Focus Status, check that Share Focus Status is enabled.")
        case .focusStatusCapabilityMissing:
            L10n.text("This build isn't provisioned to access the macOS Focus status.")
        }
    }
}
