import Foundation
import TelefonDomain

enum ProAccessError: LocalizedError {
    case required
    var errorDescription: String? { L10n.text("This feature requires TelefonX Pro.") }
}

extension PhoneModel {
    var canUseReminders: Bool { purchases.access.permits(.callReminders) }
    var canUsePublicCallerLookup: Bool {
        publicCallerLookupEnabled && purchases.access.permits(.publicCallerLookup)
    }

    func requirePro(_ feature: PaidFeature) throws {
        guard purchases.access.permits(feature) else { throw ProAccessError.required }
    }

    func effectiveRingtone(_ ringtone: LineRingtone?) -> LineRingtone {
        let selected = ringtone ?? .system(.glass)
        if case .file = selected, !purchases.access.permits(.customRingtones) { return .system(.glass) }
        return selected
    }

    func applyProAccessChange() async {
        synchronizeReminderNotifications()
        if !canUseReminders {
            preparedReminderID = nil
            reminderCalls.removeAll()
        }
        reconcileProPresentation()
        if ready { await restoreHoldMusic() }
    }
}
