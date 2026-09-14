import SwiftUI

@main struct TelefonXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = PreviewSupport.makeModel()
    @State private var settingsNavigation = SettingsNavigation()
    #if DEBUG
    @State private var previewPresentation = PreviewPresentation()
    #endif
    var body: some Scene {
        Window("TelefonX", id: "main") {
            rootView
                .environment(model)
                .environment(settingsNavigation)
                .task { if !PreviewSupport.enabled { delegate.model = model; await model.start() } }
                .task { if !PreviewSupport.enabled { await model.purchases.start() } }
                .onOpenURL { if $0.host != "show" { model.prepareDial($0.absoluteString) } }
        }
        .defaultSize(width: 1180, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            ProCommands(hasActiveSubscription: model.purchases.hasActiveSubscription)
            ListSearchCommands()
            #if DEBUG
            CommandGroup(after: .windowArrangement) {
                if PreviewSupport.enabled {
                    WindowVisibilityToggle(windowID: "preview-controls")
                }
            }
            #endif
            CommandMenu("Phone") {
                Button(model.dialText.isEmpty && model.hasRedialTarget ? "Insert This Line's Last Number" : "Place Call") {
                    Task { await model.performDialAction() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canUseDialAction)
                Button("End All Calls") { Task { for call in model.activeCalls { await model.hangup(call) } } }.disabled(model.activeCalls.isEmpty)
                Divider()
                Toggle("Do Not Disturb", isOn: Binding(get: { model.doNotDisturb }, set: { model.setDoNotDisturb($0) }))
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(!model.canSetDoNotDisturbManually)
                Button("Reconnect Lines") { Task { await model.reconnect() } }
            }
        }
        #if DEBUG
        Window("UI Preview · No Telephony", id: "preview-controls") {
            if PreviewSupport.enabled {
                PreviewControls(presentation: previewPresentation).environment(model)
            }
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()
        #endif
        Window("TelefonX Pro", id: "pro") {
            ProView()
                .environment(model)
                .disabled(PreviewSupport.enabled)
        }
        .defaultSize(width: 400, height: 600)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        Settings {
            SettingsView()
                .environment(model)
                .environment(settingsNavigation)
                .disabled(PreviewSupport.enabled)
        }
        MenuBarExtra("TelefonX", systemImage: "phone.fill", isInserted: .constant(!PreviewSupport.enabled)) {
            MenuBarView().environment(model)
        }
    }
    @ViewBuilder private var rootView: some View {
        #if DEBUG
        if PreviewSupport.enabled { PreviewHarness(presentation: previewPresentation) } else { MainView() }
        #else
        MainView()
        #endif
    }
}
