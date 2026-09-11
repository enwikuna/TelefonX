import SwiftUI
import TelefonDomain

struct GeneralSettings: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var loginItem = LoginItemManager()
    @State private var notificationAuthorization = IncomingNotifications.Authorization.unknown
    @State private var focusAuthorization = MacFocusAuthorization.notDetermined
    @AppStorage("history.hideBlockedInAll") private var hideBlockedInAll = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Open TelefonX at Login",
                    isOn: Binding(
                        get: { loginItem.isRegistered },
                        set: { enabled in Task { await loginItem.setRegistered(enabled) } }
                    )
                )
                .disabled(loginItem.busy)

                switch loginItem.status {
                case .requiresApproval:
                    LabeledContent {
                        Button("Open Login Items …") { loginItem.openSystemSettings() }
                    } label: {
                        Text("macOS still needs your approval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .notRegistered, .enabled:
                    Text("Starts TelefonX automatically so your lines are reachable after login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Calls") {
                Toggle(
                    "Start Calls from Lists Immediately",
                    isOn: Binding(
                        get: { model.automaticallyStartListCalls },
                        set: { model.setAutomaticallyStartListCalls($0) }
                    )
                )
                Text("Starts calls directly from the call button in Recents, Contacts, and Favorites. Otherwise, the number is only placed in the dialer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Pause Media During Calls",
                    isOn: Binding(
                        get: { model.pauseMediaDuringCalls },
                        set: { model.setPauseMediaDuringCalls($0) }
                    )
                )
                Text("Currently supports Apple Music and Spotify. macOS may ask for permission the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Call Waiting",
                    isOn: Binding(
                        get: { model.callWaitingEnabled },
                        set: { model.setCallWaitingEnabled($0) }
                    )
                )
                Text("Allows a second incoming call while a call is active. Without call waiting, the second call is rejected as busy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Sync with macOS Focus",
                    isOn: Binding(
                        get: { model.focusSyncEnabled },
                        set: { enabled in Task { await setFocusSyncEnabled(enabled) } }
                    )
                )
                .disabled(!MacFocusStatus.isSupportedByCurrentSignature)

                if !MacFocusStatus.isSupportedByCurrentSignature {
                    Text("This build isn't provisioned to access the macOS Focus status.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if model.focusSyncEnabled || focusAuthorization != .notDetermined {
                    LabeledContent("Focus Status", value: focusAuthorization.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("When a macOS Focus is active, TelefonX automatically declines incoming calls. Manual control is disabled while syncing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if focusAuthorization == .denied {
                    Text("Allow TelefonX to access your Focus status in System Settings to use synchronization.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Caller Information") {
                Toggle(
                    "Look Up Public Business Names",
                    isOn: Binding(
                        get: { model.canUsePublicCallerLookup },
                        set: { model.setPublicCallerLookupEnabled($0) }
                    )
                )
                .disabled(!model.purchases.access.permits(.publicCallerLookup))
                if !model.purchases.access.permits(.publicCallerLookup) {
                    ProAccessButton("Business Name Lookup with TelefonX Pro …")
                }
                Text("Looks up unknown phone numbers using Apple Maps. Local contacts always take precedence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Contacts") {
                Toggle(
                    "Show Apple Contacts",
                    isOn: Binding(
                        get: { model.appleContactsEnabled },
                        set: { enabled in Task { await model.setAppleContactsEnabled(enabled) } }
                    )
                )

                if model.appleContactsEnabled {
                    LabeledContent("Permission", value: model.appleContactsAuthorization.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if model.appleContactsAuthorization == .authorized {
                        Text(model.appleContactsLoading
                             ? L10n.text("Loading Apple Contacts …")
                             : L10n.format("%lld contacts with phone numbers are shown as read-only.",
                                           Int64(model.visibleAppleContacts.count)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.appleContactsAuthorization == .denied {
                        LabeledContent {
                            Button("Open Privacy Settings …") { model.openAppleContactsPrivacySettings() }
                        } label: {
                            Text("Allow TelefonX to access contacts in System Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if model.appleContactsAuthorization == .restricted {
                        Text("macOS currently prevents this app from accessing contacts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = model.appleContactsError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text("Shows contacts from the macOS Contacts app next to the internal address book. Apple Contacts remain read-only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recents") {
                Toggle("Hide Calls Rejected by Blocking under “All”", isOn: $hideBlockedInAll)
                Text("Earlier calls with numbers that are now blocked remain visible. Calls actually rejected by blocking are still available under “Blocked”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Call Reminders") {
                Picker(
                    "Default Notification",
                    selection: Binding(
                        get: { model.defaultReminderNotificationTiming },
                        set: { timing in
                            model.setDefaultReminderNotificationTiming(timing)
                            if timing != .none { Task { await enableReminderNotificationsIfNeeded() } }
                        }
                    )
                ) {
                    ForEach(CallReminderNotificationTiming.allCases, id: \.self) { timing in
                        Text(timing.localizedTitle).tag(timing)
                    }
                }

                if model.defaultReminderNotificationTiming != .none {
                    LabeledContent("Permission", value: notificationAuthorization.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if notificationAuthorization == .notDetermined {
                        Button("Enable Notifications …") {
                            Task { await enableReminderNotificationsIfNeeded() }
                        }
                    } else if notificationAuthorization == .denied {
                        Button("Open Notification Settings …") {
                            IncomingNotifications.openSystemSettings()
                        }
                    }
                }

                Text("The default applies to callbacks without an individual selection. You can override it in the callback dialog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { loginItem.refresh() }
        .task { notificationAuthorization = await IncomingNotifications.authorization() }
        .task { refreshFocusStatus() }
        .task { await model.refreshAppleContacts() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                loginItem.refresh()
                Task { notificationAuthorization = await IncomingNotifications.authorization() }
                refreshFocusStatus()
            }
        }
        .alert(
            "Login Item",
            isPresented: Binding(
                get: { loginItem.errorMessage != nil },
                set: { if !$0 { loginItem.errorMessage = nil } }
            )
        ) {
            Button("OK") { loginItem.errorMessage = nil }
        } message: {
            Text(loginItem.errorMessage ?? "")
        }
    }

    private func enableReminderNotificationsIfNeeded() async {
        do {
            if await IncomingNotifications.authorization() == .notDetermined {
                _ = try await IncomingNotifications.request()
            }
            notificationAuthorization = await IncomingNotifications.authorization()
            if notificationAuthorization == .allowed { model.synchronizeReminderNotifications() }
        } catch {
            model.report(error)
        }
    }

    private func setFocusSyncEnabled(_ enabled: Bool) async {
        guard enabled else {
            model.setFocusSyncEnabled(false)
            refreshFocusStatus()
            return
        }
        guard MacFocusStatus.isSupportedByCurrentSignature else {
            model.report(AppError.focusStatusCapabilityMissing)
            return
        }
        let authorization = MacFocusStatus.authorization == .notDetermined
            ? await MacFocusStatus.requestAuthorization()
            : MacFocusStatus.authorization
        focusAuthorization = authorization
        guard authorization == .authorized else {
            model.setFocusSyncEnabled(false)
            return
        }
        guard let isFocused = MacFocusStatus.isFocused else {
            model.report(AppError.focusStatusUnavailable)
            model.setFocusSyncEnabled(false)
            return
        }
        model.setMacFocusActive(isFocused)
        model.setFocusSyncEnabled(true)
    }

    private func refreshFocusStatus() {
        focusAuthorization = MacFocusStatus.authorization
        if model.focusSyncEnabled, let isFocused = MacFocusStatus.isFocused {
            model.setMacFocusActive(isFocused)
        }
    }
}
