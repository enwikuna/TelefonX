import SwiftUI

struct SettingsView: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AccountsSettings().tabItem { Label("Lines", systemImage: "network") }
            AudioSettings().tabItem { Label("Audio", systemImage: "headphones") }
            RulesSettings().tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease.circle") }
            DataSettings().tabItem { Label("Data & Diagnostics", systemImage: "externaldrive") }
        }
        .frame(width: 680, height: 570)
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
