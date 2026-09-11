import Foundation
import UserNotifications
import TelefonDomain

enum CallReminderNotifications {
    static let category = "CALL_REMINDER"
    static let callAction = "CALL_REMINDER_CALL"
    static let snoozeAction = "CALL_REMINDER_SNOOZE"
    private static let prefix = "reminder."

    static func registerActions() {
        let call = UNNotificationAction(identifier: callAction, title: L10n.text("Place Call"), options: [.foreground])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: L10n.text("10 Minutes Later"))
        let category = UNNotificationCategory(identifier: category, actions: [call, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func schedule(_ reminder: CallReminder, timing: CallReminderNotificationTiming,
                         requestAuthorization: Bool) async throws {
        guard let deliveryDate = deliveryDate(for: reminder, timing: timing) else {
            remove(reminder.id)
            return
        }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, requestAuthorization {
            guard try await center.requestAuthorization(options: [.alert, .badge, .sound]) else { return }
        } else if status != .authorized && status != .provisional { return }

        let content = UNMutableNotificationContent()
        content.title = timing.notificationTitle
        // Notes can contain confidential customer information and therefore
        // stay inside the app instead of appearing on a shared screen.
        content.body = reminder.name
        content.categoryIdentifier = category
        content.userInfo = ["reminderID": reminder.id.uuidString]
        content.sound = .default
        let interval = max(1, deliveryDate.timeIntervalSinceNow)
        let request = UNNotificationRequest(identifier: key(reminder.id), content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        if !requestAuthorization {
            let delivered = await center.deliveredNotifications()
            guard !delivered.contains(where: { $0.request.identifier == key(reminder.id) }) else { return }
        }
        center.removePendingNotificationRequests(withIdentifiers: [key(reminder.id)])
        center.removeDeliveredNotifications(withIdentifiers: [key(reminder.id)])
        try await center.add(request)
    }

    static func remove(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [key(id)])
        center.removeDeliveredNotifications(withIdentifiers: [key(id)])
    }

    static func reminderID(from response: UNNotificationResponse) -> UUID? {
        guard response.notification.request.content.categoryIdentifier == category,
              let value = response.notification.request.content.userInfo["reminderID"] as? String else { return nil }
        return UUID(uuidString: value)
    }

    static func deliveryDate(for reminder: CallReminder, timing: CallReminderNotificationTiming) -> Date? {
        timing.leadTime.map { reminder.dueAt.addingTimeInterval(-$0) }
    }

    private static func key(_ id: UUID) -> String { prefix + id.uuidString }
}

extension CallReminderNotificationTiming {
    var localizedTitle: String {
        switch self {
        case .none: L10n.text("No Notification")
        case .atTime: L10n.text("At Due Time")
        case .fiveMinutesBefore: L10n.text("5 Minutes Before")
        case .tenMinutesBefore: L10n.text("10 Minutes Before")
        }
    }

    var notificationTitle: String {
        switch self {
        case .none, .atTime: L10n.text("Callback Due")
        case .fiveMinutesBefore: L10n.text("Callback in 5 Minutes")
        case .tenMinutesBefore: L10n.text("Callback in 10 Minutes")
        }
    }
}
