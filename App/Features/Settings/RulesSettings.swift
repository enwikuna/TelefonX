import SwiftUI
import TelefonDomain

struct RulesSettings: View {
    @Environment(PhoneModel.self) private var model
    @State private var number = ""
    @State private var prefix = ""
    @State private var line: UUID?

    var body: some View {
        Form {
            Section("Call Blocking") {
                Toggle(
                    "Reject Anonymous Calls",
                    isOn: Binding(
                        get: { model.snapshot.blockAnonymous },
                        set: { value in
                            var next = model.snapshot
                            next.blockAnonymous = value
                            save(next)
                        }
                    )
                )
            }
            Section {
                HStack(spacing: 10) {
                    TextField(
                        "Phone Number or SIP Address",
                        text: $number,
                        prompt: Text("Phone Number or SIP Address")
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onSubmit(addBlock)
                    Button("Block", action: addBlock)
                        .disabled(!canAddBlock)
                }
            } header: {
                Text("New Block")
            } footer: {
                Text("Calls from this destination are rejected on all lines.")
            }
            if !model.snapshot.blocks.isEmpty {
                Section("Blocked Numbers") {
                    ForEach(model.snapshot.blocks) { rule in
                        HStack(spacing: 10) {
                            Image(systemName: "nosign")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(rule.number).textSelection(.enabled)
                            Spacer()
                            Button(role: .destructive) { removeBlock(rule.id) } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                            .help(L10n.format("Remove Block for %@", rule.number))
                            .accessibilityLabel(L10n.format("Remove Block for %@", rule.number))
                        }
                    }
                }
            }
            Section {
                Group {
                    TextField("Number Starts With", text: $prefix)
                    Picker("Use Line", selection: $line) {
                        Text("Choose a Line").tag(UUID?.none)
                        ForEach(model.snapshot.accounts) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    Button("Add Rule") {
                        guard let line else { return }
                        var next = model.snapshot
                        next.dialRules.append(DialRule(prefix: prefix, accountID: line))
                        save(next)
                        prefix = ""
                    }
                    .disabled(prefix.isEmpty || line == nil)
                    ForEach(model.snapshot.dialRules) { rule in
                        HStack {
                            Text("\(rule.prefix) → \(model.accountName(rule.accountID))")
                            Spacer()
                            Button("Remove", role: .destructive) {
                                var next = model.snapshot
                                next.dialRules.removeAll { $0.id == rule.id }
                                save(next)
                            }
                            .tint(.red)
                        }
                    }
                }
                .disabled(!dialingRulesUnlocked)
                .opacity(dialingRulesUnlocked ? 1 : 0.55)
                if !dialingRulesUnlocked {
                    ProFeatureNotice(message: "Outgoing dialing rules are available with TelefonX Pro.")
                }
            } header: {
                Label(
                    "Outgoing Dialing Rules",
                    systemImage: dialingRulesUnlocked ? "arrow.triangle.branch" : "lock.fill"
                )
            } footer: {
                Text("The longest matching prefix wins. Only registered lines are considered; otherwise, the dialer selection is used.")
            }
        }
        .formStyle(.grouped)
    }

    private var canAddBlock: Bool {
        guard let destination = try? CallDestination(number) else { return false }
        return !Routing.isBlocked(destination.value, rules: model.snapshot.blocks, anonymous: false)
    }

    private var dialingRulesUnlocked: Bool {
        model.purchases.access.permits(.dialingRules)
    }

    private func addBlock() {
        guard canAddBlock else { return }
        model.block(number)
        number = ""
    }

    private func removeBlock(_ id: UUID) {
        var next = model.snapshot
        next.blocks.removeAll { $0.id == id }
        save(next)
    }

    private func save(_ snapshot: AppSnapshot) {
        do { try model.commit(snapshot) } catch { model.report(error) }
    }
}
