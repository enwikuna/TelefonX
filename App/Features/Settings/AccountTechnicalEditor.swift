import SwiftUI
import TelefonDomain

/// Provider-specific overrides, deliberately outside everyday line editing.
struct AccountTechnicalEditor: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var account: PhoneAccount
    @State private var saving = false
    @State private var error: String?
    init(account: PhoneAccount) { _account = State(initialValue: account) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connection Help · \(account.name)").font(.title2.weight(.semibold))
                Text("Change only when your provider requires different values.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            Form {
                Section("Registration") {
                    TextField("Authentication Name", text: $account.authenticationName, prompt: Text("Empty = SIP Username"))
                    TextField("Registrar", text: $account.registrar, prompt: Text("Empty = Domain"))
                    TextField("Outbound-Proxy", text: $account.proxy, prompt: Text("Optional, Host:Port"))
                    Stepper("Registration: \(account.registrationInterval) Seconds", value: $account.registrationInterval, in: 60...3600, step: 60)
                }
                Section("Audio and Network") {
                    Toggle("Require SRTP", isOn: $account.requireSRTP).disabled(account.transport != .tls)
                    Toggle("G.711 Only (Compatibility Mode)", isOn: $account.g711Only)
                    Toggle("Enable ICE", isOn: $account.useICE)
                    Text("The best shared codec is normally selected automatically. SRTP requires TLS. STUN and TURN servers cannot be configured in this test build.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal, 22) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "Saving" : "Save") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await model.saveAccount(account, password: ""); dismiss() }
                        catch { self.error = L10n.error(error) }
                    }
                }.keyboardShortcut(.defaultAction).telefonButtonStyle(.prominent).disabled(saving)
            }.padding(20)
        }.frame(width: 580, height: 570)
    }
}
