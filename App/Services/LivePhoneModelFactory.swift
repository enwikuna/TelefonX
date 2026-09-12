import Foundation
import TelefonDomain

@MainActor enum LivePhoneModelFactory {
    private static let doNotDisturbKey = "calls.doNotDisturb"
    private static let doNotDisturbUntilKey = "calls.doNotDisturbUntil"
    private static let pauseMediaKey = "calls.pauseMedia"
    private static let callWaitingKey = "calls.callWaiting"
    private static let automaticallyStartListCallsKey = "calls.automaticallyStartListCalls"
    private static let publicCallerLookupKey = "calls.publicCallerLookup"
    private static let appleContactsKey = "contacts.apple.enabled"
    private static let reminderNotificationTimingKey = "reminders.notificationTiming"
    private static let unseenMissedCallIDsKey = "history.unseenMissedCallIDs"
    private static let focusSyncKey = "calls.focusSync"

    static func makeModel(defaults: UserDefaults = .standard) -> PhoneModel {
        var initialDoNotDisturb = defaults.bool(forKey: doNotDisturbKey)
        var initialDoNotDisturbUntil = defaults.object(forKey: doNotDisturbUntilKey) as? Date
        if let end = initialDoNotDisturbUntil, end <= Date() {
            initialDoNotDisturb = false
            initialDoNotDisturbUntil = nil
            defaults.set(false, forKey: doNotDisturbKey)
            defaults.removeObject(forKey: doNotDisturbUntilKey)
        }
        let unseenMissedCallIDs = Set(
            (defaults.stringArray(forKey: unseenMissedCallIDsKey) ?? []).compactMap(UUID.init(uuidString:))
        )
        let model = PhoneModel(
            initialDoNotDisturb: initialDoNotDisturb,
            persistDoNotDisturb: { defaults.set($0, forKey: doNotDisturbKey) },
            initialDoNotDisturbUntil: initialDoNotDisturbUntil,
            persistDoNotDisturbUntil: { value in
                if let value { defaults.set(value, forKey: doNotDisturbUntilKey) }
                else { defaults.removeObject(forKey: doNotDisturbUntilKey) }
            },
            postIncomingNotification: { IncomingNotifications.post(name: $0, line: $1, id: $2) },
            removeIncomingNotification: IncomingNotifications.remove,
            scheduleReminderNotification: CallReminderNotifications.schedule,
            removeReminderNotification: CallReminderNotifications.remove,
            requestIncomingAttention: IncomingCallAttention.request,
            cancelIncomingAttention: IncomingCallAttention.cancel,
            initialPauseMediaDuringCalls: defaults.object(forKey: pauseMediaKey) as? Bool ?? false,
            initialCallWaitingEnabled: defaults.object(forKey: callWaitingKey) as? Bool ?? true,
            persistPauseMediaDuringCalls: { defaults.set($0, forKey: pauseMediaKey) },
            persistCallWaitingEnabled: { defaults.set($0, forKey: callWaitingKey) },
            initialAutomaticallyStartListCalls: defaults.bool(forKey: automaticallyStartListCallsKey),
            persistAutomaticallyStartListCalls: { defaults.set($0, forKey: automaticallyStartListCallsKey) },
            initialPublicCallerLookupEnabled: defaults.object(forKey: publicCallerLookupKey) as? Bool ?? false,
            persistPublicCallerLookupEnabled: { defaults.set($0, forKey: publicCallerLookupKey) },
            initialReminderNotificationTiming: CallReminderNotificationTiming(
                rawValue: defaults.string(forKey: reminderNotificationTimingKey) ?? ""
            ) ?? .atTime,
            persistReminderNotificationTiming: { defaults.set($0.rawValue, forKey: reminderNotificationTimingKey) },
            initialAppleContactsEnabled: defaults.bool(forKey: appleContactsKey),
            persistAppleContactsEnabled: { defaults.set($0, forKey: appleContactsKey) },
            initialUnseenMissedCallIDs: unseenMissedCallIDs,
            persistUnseenMissedCallIDs: { ids in
                defaults.set(ids.map(\.uuidString).sorted(), forKey: unseenMissedCallIDsKey)
            },
            initialFocusSyncEnabled: defaults.bool(forKey: focusSyncKey),
            persistFocusSyncEnabled: { defaults.set($0, forKey: focusSyncKey) },
            purchases: PurchaseStore(internalEvaluation: false)
        )
        model.removeUnreferencedAudioFiles()
        return model
    }
}
