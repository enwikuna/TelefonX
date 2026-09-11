import AppKit
import SwiftUI
import TelefonDomain

struct DataSettings: View {
    @Environment(PhoneModel.self) private var model
    @State private var keychainResult: String?
    @State private var technicalAccount: PhoneAccount?

    var body: some View {
        Form {
            localDataSection
            if !model.activeCalls.isEmpty {
                callQualitySection
            }
            diagnosticsSection
            connectionHelpSection
            if model.purchases.internalEvaluation {
                internalBuildSection
            }
        }
        .formStyle(.grouped)
        .sheet(item: $technicalAccount) {
            AccountTechnicalEditor(account: $0).environment(model)
        }
        .alert(
            "Keychain Check",
            isPresented: Binding(
                get: { keychainResult != nil },
                set: { if !$0 { keychainResult = nil } }
            )
        ) {
            Button("OK") { keychainResult = nil }
        } message: {
            Text(keychainResult ?? "")
        }
    }

    private var localDataSection: some View {
        Section("Local Data") {
            LabeledContent("Storage", value: "Only on This Mac · No Cloud Sync")
            Button("Export Backup …") { FileActions.exportBackup(model) }
            Button("Restore Backup …") { FileActions.importBackup(model) }
                .disabled(!model.activeCalls.isEmpty)
            Text("Backups include contacts, contact photos, notes, line names, recents, and callbacks, but no passwords or audio files. Choose custom sounds again on another Mac. The backup contains personal data and is not encrypted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var callQualitySection: some View {
        Section("Active Calls · Audio Quality") {
            ForEach(model.activeCalls) { call in
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.accountName(call.accountID)).font(.headline)
                    if let quality = call.quality {
                        Text("\(quality.codec) · \(quality.clockRate / 1000) kHz · \(quality.receivedPackets) RTP packets")
                        Text("Loss \(quality.lossPercent, specifier: "%.1f")% · Jitter \(quality.jitterMilliseconds, specifier: "%.1f") ms")
                        Text("RTT \(quality.roundTripMilliseconds, specifier: "%.0f") ms · \(quality.secureMedia ? L10n.text("SRTP Active") : L10n.text("Unencrypted RTP"))")
                        if quality.receivedPackets == 0 {
                            Text("No incoming audio packets yet.")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("Measuring audio quality …")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            LabeledContent("Engine", value: "PJSIP 2.17 · Opus 1.5.2")
            LabeledContent("Audio", value: "Opus / G.722 / G.711 · WebRTC AEC3")
            LabeledContent("Platform", value: "Apple Silicon · macOS 26+")
            Button("Export Anonymized Diagnostics …") { FileActions.exportDiagnostics(model) }
            Button("Check Keychain", action: checkKeychain)
            Text("The diagnostics export contains no passwords, phone numbers, contact names, or call content.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionHelpSection: some View {
        Section("Connection Help") {
            ForEach(model.snapshot.accounts) { account in
                LabeledContent(account.name) {
                    Button("Technical Options …") { technicalAccount = account }
                        .disabled(!model.activeCalls.isEmpty)
                }
            }
            Button("Rebuild SIP Connections") {
                Task { await model.reconnect() }
            }
            Text("For provider-specific registration, proxy, and audio compatibility settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var internalBuildSection: some View {
        Section("Internal Test Build") {
            Text("All features are unlocked for testing. No purchase or subscription is active.")
            Text("Not yet approved for the App Store or production distribution. SIP licensing, signing, sandboxing, and real-world testing are separate release requirements.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Show License Notices …") {
                guard let url = Bundle.main.resourceURL?.appending(path: "ThirdParty") else { return }
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func checkKeychain() {
        do {
            try KeychainCheck.run()
            keychainResult = L10n.text("Keychain is working: a test value was saved, read, and removed. Your SIP passwords were not read or changed.")
        } catch {
            keychainResult = L10n.error(error)
        }
    }
}
