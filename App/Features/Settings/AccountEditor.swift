import SwiftUI
import TelefonDomain

struct AccountEditor: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var account: PhoneAccount
    @State private var password = ""
    @State private var error: String?
    @State private var saving = false
    init(account: PhoneAccount) { _account = State(initialValue: account) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("SIP Line").font(.title2.weight(.semibold)); Spacer(); Image(systemName: "network").foregroundStyle(.secondary) }.padding(22)
            Form {
                Section {
                    TextField("Name", text: $account.name, prompt: Text("Office · Home · Location"))
                    TextField("Domain / Server", text: $account.domain, prompt: Text("sip.example.com"))
                    TextField("SIP Username", text: $account.username)
                    SecureField("Password", text: $password, prompt: Text("Empty = Keep Existing"))
                    Picker("Connection", selection: $account.transport) {
                        Text("Default (UDP)").tag(SIPTransport.udp)
                        Text("TCP").tag(SIPTransport.tcp)
                        Text("TLS · Encrypted Signaling").tag(SIPTransport.tls)
                    }
                    Toggle("Line Enabled", isOn: $account.enabled)
                } footer: {
                    Text("Your provider or phone-system administrator supplies the SIP credentials. They may differ from your customer-account credentials.")
                }
                Section {
                    Toggle("Hide My Caller ID", isOn: $account.suppressCallerID)
                } header: {
                    Text("Outgoing Calls")
                } footer: {
                    Text("TelefonX requests caller-ID suppression over SIP. Your provider or phone system must support this feature.")
                }
                RingtonePicker(selection: $account.ringtone)
            }.formStyle(.grouped)
            if let error {
                Text(error)
                    .telefonDialogErrorStyle()
            }
            HStack {
                Label("Password in Keychain", systemImage: "key").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "Saving" : "Save") {
                    saving = true
                    Task {
                        do { try await model.saveAccount(account, password: password); password = ""; dismiss() }
                        catch { self.error = L10n.error(error) }
                        saving = false
                    }
                }.keyboardShortcut(.defaultAction).telefonButtonStyle(.prominent).disabled(saving)
            }.padding(20)
        }.frame(width: 580, height: 630)
        .onChange(of: account.transport) { _, value in if value != .tls { account.requireSRTP = false } }
    }
}
