import AppKit
import Contacts
import Network
import Observation
import OSLog
import UserNotifications

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: PhoneModel? {
        didSet {
            consumePendingReminderResponse()
            observeDockBadge()
            observeFocusSyncPreference()
        }
    }
    private var pendingReminderResponse: (id: UUID, action: String)?
    private var focusSyncTask: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private var observedPath = false
    private let logger = Logger(subsystem: "de.enwikuna.TelefonX", category: "Network")
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PreviewSupport.enabled else { return }
        NSApp.servicesProvider = self
        UNUserNotificationCenter.current().delegate = self
        CallReminderNotifications.registerActions()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contactsDidChange),
                                               name: .CNContactStoreDidChange, object: nil)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let status = switch path.status {
                case .satisfied: "available"
                case .unsatisfied: "unavailable"
                case .requiresConnection: "requires-connection"
                @unknown default: "unknown"
                }
                self.logger.notice("Network path update: \(status, privacy: .public)")
                if self.observedPath { self.model?.scheduleNetworkRefresh() }
                self.observedPath = true
            }
        }
        monitor.start(queue: DispatchQueue(label: "de.enwikuna.TelefonX.network"))
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.activeCalls.isEmpty == false {
            let alert = NSAlert(); alert.messageText = L10n.text("End Active Calls?")
            alert.informativeText = L10n.text("Quitting TelefonX disconnects all calls.")
            alert.addButton(withTitle: L10n.text("Quit")); alert.addButton(withTitle: L10n.text("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        monitor.cancel()
        focusSyncTask?.cancel()
        Task { await model?.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    @objc private func didWake() {
        model?.expireDoNotDisturbIfNeeded()
        model?.scheduleNetworkRefresh()
    }
    @objc private func contactsDidChange() { Task { await model?.refreshAppleContacts() } }
    func applicationDidBecomeActive(_ notification: Notification) {
        model?.expireDoNotDisturbIfNeeded()
        Task {
            await model?.refreshAppleContacts()
            await model?.purchases.refreshEntitlements()
        }
    }
    @objc func dialSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let value = pasteboard.string(forType: .string) else { return }
        model?.prepareDial(value)
        if let url = URL(string: "telefonx://call/" + (value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")) {
            NSWorkspace.shared.open(url)
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let reminderID = CallReminderNotifications.reminderID(from: response)
        let actionIdentifier = response.actionIdentifier
        await MainActor.run {
            if let id = reminderID {
                guard model != nil else {
                    pendingReminderResponse = (id, actionIdentifier)
                    return
                }
                handleReminderResponse(id: id, action: actionIdentifier)
                if actionIdentifier == CallReminderNotifications.snoozeAction { return }
            }
            if let url = URL(string: "telefonx://show") { NSWorkspace.shared.open(url) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.content.categoryIdentifier == CallReminderNotifications.category else { return [] }
        return [.banner, .list, .sound]
    }

    private func consumePendingReminderResponse() {
        guard model != nil, let response = pendingReminderResponse else { return }
        pendingReminderResponse = nil
        handleReminderResponse(id: response.id, action: response.action)
    }

    private func observeDockBadge() {
        guard let model else {
            DockBadge.update(missedCallCount: 0)
            return
        }
        let count = withObservationTracking {
            model.missedCallBadgeCount
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeDockBadge() }
        }
        DockBadge.update(missedCallCount: count)
    }

    private func observeFocusSyncPreference() {
        guard let model else {
            focusSyncTask?.cancel()
            focusSyncTask = nil
            return
        }
        let enabled = withObservationTracking {
            model.focusSyncEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeFocusSyncPreference() }
        }
        focusSyncTask?.cancel()
        focusSyncTask = nil
        guard enabled else {
            model.setMacFocusActive(false)
            return
        }
        guard MacFocusStatus.isSupportedByCurrentSignature else {
            model.setFocusSyncEnabled(false)
            model.report(AppError.focusStatusCapabilityMissing)
            return
        }
        focusSyncTask = Task { [weak model] in
            while !Task.isCancelled, let model {
                if let isFocused = MacFocusStatus.isFocused {
                    model.setMacFocusActive(isFocused)
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func handleReminderResponse(id: UUID, action: String) {
        if action == CallReminderNotifications.snoozeAction {
            try? model?.snoozeReminder(id)
            return
        }
        if action == CallReminderNotifications.callAction { model?.prepareReminderCall(id) }
        NotificationCenter.default.post(name: .showCallReminders, object: nil)
    }
}

extension Notification.Name {
    static let showCallReminders = Notification.Name("de.enwikuna.TelefonX.showCallReminders")
}
