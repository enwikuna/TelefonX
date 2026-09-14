import SwiftUI

enum SettingsSection: Hashable {
    case general
    case lines
    case audio
    case rules
    case data
}

@Observable @MainActor final class SettingsNavigation {
    var selection: SettingsSection = .general
}

struct SettingsView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selection) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsSection.general)
            AccountsSettings()
                .tabItem { Label("Lines", systemImage: "network") }
                .tag(SettingsSection.lines)
            AudioSettings()
                .tabItem { Label("Audio", systemImage: "headphones") }
                .tag(SettingsSection.audio)
            RulesSettings()
                .tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease.circle") }
                .tag(SettingsSection.rules)
            DataSettings()
                .tabItem { Label("Data & Diagnostics", systemImage: "externaldrive") }
                .tag(SettingsSection.data)
        }
        .frame(width: 680, height: 570)
        .settingsWindowToolbarAppearanceOnMacOS27()
        .alert(
            "TelefonX",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
