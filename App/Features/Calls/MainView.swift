import SwiftUI
import TelefonDomain

struct MainView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @Environment(\.openSettings) private var openSettings
    private let initialSection: PhoneSection?
    @State private var section: PhoneSection?
    @State private var searchStates = SectionSearchStates()
    @State private var showNotificationOffer = false
    @AppStorage("notifications.offerPresented") private var notificationOfferPresented = false
    init(initialSection: PhoneSection? = .history) {
        self.initialSection = initialSection
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        navigation
        .navigationSplitViewStyle(.balanced)
        .background { WindowToolbarSeparation() }
        .overlay(alignment: .trailing) {
            if PhoneWorkspaceToolbarPresentation.showsWorkspace(accountCount: model.snapshot.accounts.count) {
                // Extend the noninteractive column separator through the titlebar.
                HStack(spacing: 0) {
                    Divider()
                    Color.clear.frame(width: MainSplitViewLayout.detailWidth)
                }
                .fixedSize(horizontal: true, vertical: false)
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .focusedSceneValue(\.focusListSearch, focusSearch)
        .frame(minWidth: MainSplitViewLayout.minimumWindowWidth, minHeight: 640)
        .task(id: model.registeredCount) {
            guard !PreviewSupport.enabled, model.registeredCount > 0, !notificationOfferPresented else { return }
            let authorization = await IncomingNotifications.authorization()
            notificationOfferPresented = true
            if authorization == .notDetermined { showNotificationOffer = true }
        }
        .alert("Enable Incoming Call Notifications?", isPresented: $showNotificationOffer) {
            Button("Later", role: .cancel) {}
            Button("Enable …") {
                Task {
                    do { _ = try await IncomingNotifications.request() }
                    catch { model.report(error) }
                }
            }
        } message: {
            Text("TelefonX can notify you about incoming calls when its window is not in the foreground.")
        }
        .alert("TelefonX", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("TelefonX", isPresented: Binding(get: { model.information != nil }, set: { if !$0 { model.information = nil } })) {
            Button("OK") { model.information = nil }
        } message: { Text(model.information ?? "") }
        .onChange(of: initialSection) { _, value in section = value }
        .onReceive(NotificationCenter.default.publisher(for: .showCallReminders)) { _ in section = .reminders }
    }

    private var navigation: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarColumn
        } detail: {
            HStack(spacing: 0) {
                contentColumn
                if PhoneWorkspaceToolbarPresentation.showsWorkspace(accountCount: model.snapshot.accounts.count) {
                    CallWorkspace()
                        .frame(width: MainSplitViewLayout.detailWidth)
                        .toolbar { phoneWorkspaceToolbar }
                }
            }
        }
    }

    private var sidebarColumn: some View {
        SidebarView(selection: $section)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(
                min: MainSplitViewLayout.sidebarWidth,
                ideal: MainSplitViewLayout.sidebarWidth,
                max: MainSplitViewLayout.sidebarWidth
            )
            .background { FixedSidebarConfiguration(width: MainSplitViewLayout.sidebarWidth) }
    }

    private var contentColumn: some View {
        Group {
            if model.storageError != nil {
                ContentUnavailableView("Data Store Unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(model.storageError ?? ""))
                    .windowCenteredEmptyState()
                    .scrollableEmptyState()
            } else if model.snapshot.accounts.isEmpty && section == .history {
                ContentUnavailableView {
                    Label("Your Mac. Your Phone.", systemImage: "phone.connection")
                } description: {
                    Text("Connect your first SIP line.\nCalls, contacts, and every location in one place.")
                } actions: {
                    VStack(spacing: 10) {
                        Button {
                            settingsNavigation.selection = .lines
                            openSettings()
                        } label: {
                            Text("Configure a Line in Settings …")
                        }
                            .telefonButtonStyle(.prominent)
                        if !model.snapshot.history.isEmpty {
                            Button("Export Saved Recents …") { FileActions.exportHistoryCSV(model) }
                        }
                    }
                }
                .windowCenteredEmptyState()
                .listToolbarTitle("Recents", subtitle: L10n.text("No Line"))
                .scrollableEmptyState()
            } else if section == .contacts || section == .favorites {
                ContactsView(searchState: searchState(for: section ?? .contacts),
                             favoritesOnly: section == .favorites)
                    .id(section)
            } else if section == .reminders {
                CallRemindersView(searchState: searchState(for: .reminders))
            } else {
                HistoryView(searchState: searchState(for: .history), showFavorites: { section = .favorites })
            }
        }
        .frame(
            minWidth: MainSplitViewLayout.minimumContentWidth,
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .navigationTitle(section?.title ?? "TelefonX")
    }
    private var focusSearch: (() -> Void)? {
        guard model.storageError == nil,
              section != .history || !model.snapshot.accounts.isEmpty else { return nil }
        let activeSection = section ?? .history
        return {
            var state = searchStates[activeSection]
            state.focus()
            searchStates[activeSection] = state
        }
    }

    private func searchState(for section: PhoneSection) -> Binding<ListSearchState> {
        Binding(
            get: { searchStates[section] },
            set: { searchStates[section] = $0 }
        )
    }

    @ToolbarContentBuilder private var phoneWorkspaceToolbar: some ToolbarContent {
        ToolbarItem(id: "phone-workspace-toolbar", placement: .primaryAction) {
            PhoneWorkspaceToolbarRow()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

private struct PhoneWorkspaceToolbarRow: View {
    var body: some View {
        HStack(spacing: 0) {
            CallerIDToolbarSlot()
            Spacer(minLength: 0)
            PhoneWorkspaceTitle()
            Spacer(minLength: 0)
            DoNotDisturbToolbarSlot()
        }
        .frame(width: MainSplitViewLayout.detailWidth - 2 * CallWorkspaceLayout.horizontalContentInset)
        // Match the content inset rather than the native toolbar's 8 pt margin.
        .offset(x: 8 - CallWorkspaceLayout.horizontalContentInset)
        // Keep the reserved slot independent of padding so list controls stay aligned.
        .frame(width: PhoneWorkspaceToolbarPresentation.reservedWidth, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }
}

enum PhoneWorkspaceToolbarPresentation {
    static let reservedWidth: CGFloat = MainSplitViewLayout.detailWidth - 24
    static func showsWorkspace(accountCount: Int) -> Bool { accountCount > 0 }
    static func showsDoNotDisturb(accountCount: Int) -> Bool { accountCount > 0 }

}

enum MainSplitViewLayout {
    static let sidebarWidth: CGFloat = 220
    static let minimumContentWidth: CGFloat = 480
    static let detailWidth: CGFloat = 330
    // Preserve room for the contacts toolbar as well as the three content areas.
    static let minimumWindowWidth: CGFloat = 1120
}

private let phoneWorkspaceToolbarControlSize: CGFloat = 38

private struct PhoneWorkspaceLockedStatusIcon: View {
    let systemName: String
    var isActive = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
            Image(systemName: "lock.fill")
                .font(.system(size: 7, weight: .bold))
                .padding(1)
                .background(.bar, in: Circle())
                .offset(x: 4, y: 3)
        }
        .frame(width: phoneWorkspaceToolbarControlSize,
               height: phoneWorkspaceToolbarControlSize)
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.55))
        .phoneWorkspaceToolbarStatusSurface()
    }
}

private struct CallerIDToolbarSlot: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        if model.presentedCalls.isEmpty, model.selectedAccount != nil {
            CallerIDSuppressionButton()
        } else {
            Color.clear.frame(width: phoneWorkspaceToolbarControlSize,
                              height: phoneWorkspaceToolbarControlSize)
        }
    }
}

private struct PhoneWorkspaceTitle: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        Text(model.presentedCalls.isEmpty ? "Phone" : "Call")
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

private struct CallerIDSuppressionButton: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        if model.selectedAccountAlwaysSuppressesCallerID {
            PhoneWorkspaceLockedStatusIcon(systemName: "shield.fill")
            .help("Caller ID is permanently hidden for this line. Change it in Settings.")
            .accessibilityElement()
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Hide Caller ID")
            .accessibilityValue("Permanently enabled in Settings")
            .accessibilityIdentifier("caller-id-suppression")
        } else {
            Button { model.toggleCallerIDSuppressionForNextCall() } label: {
                Image(systemName: model.suppressCallerIDOnce ? "shield.fill" : "shield")
                    .foregroundStyle(model.suppressCallerIDOnce ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Circle())
            }
            .phoneWorkspaceToolbarButtonSurface()
            .help(model.suppressCallerIDOnce
                  ? "Disable Caller ID Hiding for Next Call"
                  : "Hide Caller ID for Next Call")
            .accessibilityLabel("Hide Caller ID for Next Call")
            .accessibilityValue(model.suppressCallerIDOnce ? "Active" : "Off")
            .accessibilityIdentifier("caller-id-suppression")
        }
    }
}

private extension View {
    @ViewBuilder func phoneWorkspaceToolbarStatusSurface() -> some View {
        glassEffect(.regular, in: .circle)
    }

    @ViewBuilder func phoneWorkspaceToolbarButtonSurface() -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .frame(width: phoneWorkspaceToolbarControlSize,
                   height: phoneWorkspaceToolbarControlSize)
    }
}

private struct DoNotDisturbButton: View {
    @Environment(PhoneModel.self) private var model
    @State private var showsActivationOptions = false

    @ViewBuilder
    var body: some View {
        if model.focusSyncEnabled {
            PhoneWorkspaceLockedStatusIcon(
                systemName: model.doNotDisturb ? "bell.slash.fill" : "bell",
                isActive: model.doNotDisturb
            )
            .help("Do Not Disturb is synchronized with macOS Focus")
            .accessibilityElement()
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Do Not Disturb")
            .accessibilityValue(model.doNotDisturb ? "On · synchronized with macOS Focus" : "Off · synchronized with macOS Focus")
            .accessibilityIdentifier("do-not-disturb")
        } else {
            Button {
                if model.manualDoNotDisturb {
                    model.setDoNotDisturb(false)
                } else {
                    showsActivationOptions = true
                }
            } label: {
                Image(systemName: model.doNotDisturb ? "bell.slash.fill" : "bell")
                    .foregroundStyle(model.doNotDisturb ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Circle())
            }
            .phoneWorkspaceToolbarButtonSurface()
            .overlay {
                NativeDoNotDisturbMenuPresenter(isPresented: $showsActivationOptions) { duration in
                    model.activateDoNotDisturb(for: duration)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .help(model.doNotDisturb ? "Disable Do Not Disturb" : "Enable Do Not Disturb")
            .accessibilityLabel("Do Not Disturb")
            .accessibilityValue(model.doNotDisturb ? "Active" : "Off")
            .accessibilityIdentifier("do-not-disturb")
        }
    }
}

private struct DoNotDisturbToolbarSlot: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        Group {
            if PhoneWorkspaceToolbarPresentation.showsDoNotDisturb(accountCount: model.snapshot.accounts.count) {
                DoNotDisturbButton()
            } else {
                // Preserve the symmetric toolbar geometry so the title stays
                // centered while omitting an action that has no effect.
                Color.clear
                    .frame(width: phoneWorkspaceToolbarControlSize,
                           height: phoneWorkspaceToolbarControlSize)
                    .accessibilityHidden(true)
            }
        }
    }
}
