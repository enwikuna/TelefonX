import Foundation
import TelefonDomain

extension PhoneModel {
    var pendingReminders: [CallReminder] { canUseReminders ? snapshot.reminders.filter { $0.completedAt == nil } : [] }

    func reminderDraft(for record: CallRecord, dueAt: Date = Date().addingTimeInterval(60 * 60)) -> CallReminder {
        CallReminder(name: displayName(record.remote), number: record.remote, dueAt: dueAt,
                     accountID: snapshot.accounts.contains(where: { $0.id == record.accountID }) ? record.accountID : nil,
                     contactID: contact(for: record.remote)?.id, sourceCallID: record.id)
    }

    func saveReminder(_ reminder: CallReminder) throws {
        try requirePro(.callReminders)
        guard reminder.completedAt != nil || reminder.dueAt > Date() else { throw AppError.reminderDateInPast }
        var next = snapshot
        if let index = next.reminders.firstIndex(where: { $0.id == reminder.id }) {
            next.reminders[index] = reminder
        } else {
            next.reminders.append(reminder)
        }
        try commit(next, changes: SnapshotChanges(preferences: true))
        if reminder.completedAt == nil {
            scheduleReminder(reminder, requestingAuthorization: true)
        } else {
            removeReminderNotification(reminder.id)
        }
    }

    func completeReminder(_ id: UUID, completed: Bool = true) throws {
        try requirePro(.callReminders)
        guard let reminder = snapshot.reminders.first(where: { $0.id == id }) else { return }
        guard completed || reminder.dueAt > Date() else { throw AppError.reminderDateInPast }
        var updated = reminder
        updated.completedAt = completed ? Date() : nil
        try saveReminderWithoutAuthorization(updated)
    }

    func snoozeReminder(_ id: UUID, by interval: TimeInterval = 10 * 60) throws {
        try requirePro(.callReminders)
        guard let reminder = snapshot.reminders.first(where: { $0.id == id }) else { return }
        var updated = reminder
        updated.dueAt = Date().addingTimeInterval(interval)
        updated.completedAt = nil
        try saveReminderWithoutAuthorization(updated)
    }

    func deleteReminders(_ ids: Set<UUID>) throws {
        try requirePro(.callReminders)
        let removed = snapshot.reminders.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        var next = snapshot
        next.reminders.removeAll { ids.contains($0.id) }
        try commit(next, changes: SnapshotChanges(preferences: true))
        for reminder in removed { removeReminderNotification(reminder.id) }
    }

    func completeReminders(_ ids: Set<UUID>) throws {
        try requirePro(.callReminders)
        let pendingIDs = Set(snapshot.reminders.filter { ids.contains($0.id) && $0.completedAt == nil }.map(\.id))
        guard !pendingIDs.isEmpty else { return }
        var next = snapshot
        let completedAt = Date()
        for index in next.reminders.indices where pendingIDs.contains(next.reminders[index].id) {
            next.reminders[index].completedAt = completedAt
        }
        try commit(next, changes: SnapshotChanges(preferences: true))
        for id in pendingIDs { removeReminderNotification(id) }
    }

    func prepareReminderCall(_ id: UUID) {
        guard canUseReminders else { return }
        guard let reminder = snapshot.reminders.first(where: { $0.id == id }) else { return }
        let accountID = availableReminderAccountID(reminder)
        if prepareDial(reminder.number, accountID: accountID) { preparedReminderID = id }
    }

    func performReminderListAction(_ id: UUID) async {
        guard canUseReminders else { return }
        guard let reminder = snapshot.reminders.first(where: { $0.id == id }) else { return }
        let wasIdle = activeCalls.isEmpty
        let handle = await performListCall(reminder.number, preferredAccountID: availableReminderAccountID(reminder),
                                           allowsAutomaticStart: false)
        if let handle {
            associateReminder(id, with: handle)
        } else if wasIdle, dialText == (try? CallDestination(reminder.number).value) {
            preparedReminderID = id
        }
    }

    func callReminderNow(_ id: UUID) async {
        guard canUseReminders else { return }
        guard let reminder = snapshot.reminders.first(where: { $0.id == id }) else { return }
        let handle = await callNumber(reminder.number, preferredAccountID: availableReminderAccountID(reminder))
        associateReminder(id, with: handle)
    }

    func canCallReminder(_ reminder: CallReminder) -> Bool {
        canUseReminders && canCall(reminder.number, preferredAccountID: availableReminderAccountID(reminder))
    }

    func synchronizeReminderNotifications() {
        guard canUseReminders else {
            for reminder in snapshot.reminders { removeReminderNotification(reminder.id) }
            return
        }
        for reminder in pendingReminders { scheduleReminder(reminder, requestingAuthorization: false) }
    }

    private func saveReminderWithoutAuthorization(_ reminder: CallReminder) throws {
        var next = snapshot
        guard let index = next.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        next.reminders[index] = reminder
        try commit(next, changes: SnapshotChanges(preferences: true))
        if reminder.completedAt == nil {
            scheduleReminder(reminder, requestingAuthorization: false)
        } else {
            removeReminderNotification(reminder.id)
        }
    }

    private func availableReminderAccountID(_ reminder: CallReminder) -> UUID? {
        reminder.accountID.flatMap { id in snapshot.accounts.contains(where: { $0.id == id }) ? id : nil }
    }

    func preparedReminder(for value: String) -> UUID? {
        guard canUseReminders, let id = preparedReminderID,
              let reminder = snapshot.reminders.first(where: { $0.id == id && $0.completedAt == nil }),
              let destination = try? CallDestination(value),
              let reminderDestination = try? CallDestination(reminder.number),
              destination.matchingKey() == reminderDestination.matchingKey() else { return nil }
        return id
    }

    func associateReminder(_ id: UUID?, with handle: CallHandle?) {
        guard canUseReminders, let id, let handle else { return }
        reminderCalls[handle] = id
    }

    func finishReminderCall(_ handle: CallHandle, wasConnected: Bool) {
        guard canUseReminders, let id = reminderCalls.removeValue(forKey: handle), wasConnected,
              let reminder = snapshot.reminders.first(where: { $0.id == id }),
              reminder.completedAt == nil, reminder.dueAt <= Date() else { return }
        do { try completeReminder(id) } catch { report(error) }
    }

    private func scheduleReminder(_ reminder: CallReminder, requestingAuthorization: Bool) {
        guard canUseReminders else { removeReminderNotification(reminder.id); return }
        let timing = reminder.notificationTiming ?? defaultReminderNotificationTiming
        guard timing != .none else {
            removeReminderNotification(reminder.id)
            return
        }
        Task { [weak self] in
            guard let self, self.canUseReminders else { return }
            do {
                try await self.scheduleReminderNotification(reminder, timing, requestingAuthorization)
                if !self.canUseReminders { self.removeReminderNotification(reminder.id) }
            }
            catch { self.report(error) }
        }
    }
}
