import AppKit
import SwiftUI
import TelefonDomain
import UniformTypeIdentifiers

struct AccountsSettings: View {
    @Environment(PhoneModel.self) private var model
    @State private var editing: PhoneAccount?
    @State private var deleting: PhoneAccount?
    @State private var draggingAccountID: UUID?
    @State private var dropTarget: AccountDropTarget?

    var body: some View {
        Form {
            Section {
                ForEach(model.snapshot.accounts) { account in
                    let locked = model.isAccountLockedByPro(account.id)
                    let state = model.registrations[account.id] ?? .offline
                    HStack {
                        if locked {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 7)
                                .help("Locked · TelefonX Pro")
                        } else {
                            RegistrationIndicator(state: state)
                        }
                        VStack(alignment: .leading) {
                            Text(account.name)
                            Text("\(account.username)@\(account.domain)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !locked, showsReconnect(account, state: state) {
                            Button("Reconnect") { Task { await model.reconnect(accountID: account.id) } }
                        }
                        if locked {
                            ProAccessButton("Unlock with TelefonX Pro …")
                        } else {
                            Button("Edit …") { editing = account }
                                .disabled(!model.activeCalls.isEmpty)
                        }
                        Button(role: .destructive) { deleting = account } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                        .accessibilityLabel("Delete Line …")
                        .disabled(!model.activeCalls.isEmpty)

                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, height: 24)
                            .contentShape(Rectangle())
                            .help("Drag to Reorder")
                            .accessibilityLabel("Drag Line to Reorder")
                    }
                    .contentShape(Rectangle())
                    .padding(.top, dropTarget == .init(id: account.id, placement: .before) ? 9 : 0)
                    .padding(.bottom, dropTarget == .init(id: account.id, placement: .after) ? 9 : 0)
                    .overlay(alignment: .top) {
                        if dropTarget == .init(id: account.id, placement: .before) {
                            insertionIndicator.offset(y: -5)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if dropTarget == .init(id: account.id, placement: .after) {
                            insertionIndicator.offset(y: 5)
                        }
                    }
                    .animation(.snappy(duration: 0.16), value: dropTarget)
                    .onDrag {
                        dropTarget = nil
                        draggingAccountID = account.id
                        return NSItemProvider(object: account.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: AccountDropDelegate(
                            targetID: account.id,
                            accountIDs: model.snapshot.accounts.map(\.id),
                            draggingID: $draggingAccountID,
                            dropTarget: $dropTarget,
                            move: model.moveAccount(_:over:)
                        )
                    )
                    .contextMenu {
                        Button("Move Up", systemImage: "arrow.up") {
                            model.moveAccount(account.id, by: -1)
                        }
                        .disabled(model.snapshot.accounts.first?.id == account.id)

                        Button("Move Down", systemImage: "arrow.down") {
                            model.moveAccount(account.id, by: 1)
                        }
                        .disabled(model.snapshot.accounts.last?.id == account.id)
                    }
                }
                if model.snapshot.accounts.isEmpty
                    || model.purchases.access.permits(.additionalLines) {
                    Button("Add Line …") { editing = PhoneAccount() }
                        .disabled(!model.activeCalls.isEmpty)
                } else {
                    ProAccessButton("Add Another Line with TelefonX Pro …")
                }
            } header: {
                Text("Your SIP Lines")
            } footer: {
                if model.purchases.access.permits(.additionalLines) {
                    Text("Drag the handle to change the order. All lines remain registered at the same time. Line editing is disabled during a call.")
                } else if model.snapshot.accounts.count > 1 {
                    Text("Without Pro, only the first line is active. Drag a line to the first position to choose it. Locked lines and their settings remain saved.")
                } else {
                    Text("Drag the handle to change the order. Line editing is disabled during a call.")
                }
            }

            Section {
                Picker(
                    "Default Line",
                    selection: Binding(
                        get: { model.snapshot.defaultAccountID },
                        set: { id in
                            var next = model.snapshot
                            next.defaultAccountID = id
                            do { try model.commit(next) } catch { model.report(error) }
                        }
                    )
                ) {
                    Text("None").tag(UUID?.none)
                    ForEach(model.snapshot.accounts) { account in
                        Label(account.name, systemImage: model.isAccountLockedByPro(account.id) ? "lock.fill" : "network")
                            .tag(Optional(account.id))
                            .disabled(model.isAccountLockedByPro(account.id))
                    }
                }
                NotificationSettingsRow()
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) {
            AccountEditor(account: $0).environment(model)
        }
        .confirmationDialog(
            "Delete Line?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Line and Password", role: .destructive) {
                guard let deleting else { return }
                Task {
                    do { try await model.deleteAccount(deleting.id) }
                    catch { model.report(error) }
                    self.deleting = nil
                }
            }
        } message: {
            Text("The credentials are removed. Call history is retained.")
        }
    }

    private func showsReconnect(_ account: PhoneAccount, state: RegistrationState) -> Bool {
        guard model.ready, account.enabled else { return false }
        switch state {
        case .failed, .offline:
            return true
        case .disabled, .registering, .registered:
            return false
        }
    }

    private var insertionIndicator: some View {
        HStack(spacing: 0) {
            Circle().frame(width: 6, height: 6)
            Rectangle().frame(height: 2)
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, 2)
        .accessibilityHidden(true)
    }
}

private struct AccountDropTarget: Equatable {
    enum Placement: Equatable { case before, after }
    let id: UUID
    let placement: Placement
}

private struct AccountDropDelegate: DropDelegate {
    let targetID: UUID
    let accountIDs: [UUID]
    @Binding var draggingID: UUID?
    @Binding var dropTarget: AccountDropTarget?
    let move: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID,
              let sourceIndex = accountIDs.firstIndex(of: draggingID),
              let targetIndex = accountIDs.firstIndex(of: targetID) else {
            dropTarget = nil
            return
        }
        let placement: AccountDropTarget.Placement = sourceIndex < targetIndex ? .after : .before
        withAnimation(.snappy(duration: 0.16)) {
            dropTarget = AccountDropTarget(id: targetID, placement: placement)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingID, dropTarget?.id == targetID else {
            self.draggingID = nil
            dropTarget = nil
            return false
        }
        move(draggingID, targetID)
        self.draggingID = nil
        dropTarget = nil
        return true
    }

    func dropExited(info: DropInfo) {
        guard dropTarget?.id == targetID else { return }
        withAnimation(.snappy(duration: 0.12)) { dropTarget = nil }
    }
}

private struct NotificationSettingsRow: View {
    @Environment(PhoneModel.self) private var model
    @State private var authorization = IncomingNotifications.Authorization.unknown

    var body: some View {
        LabeledContent("Call and Callback Notifications") {
            HStack(spacing: 10) {
                Text(authorization.label).foregroundStyle(.secondary)
                switch authorization {
                case .notDetermined:
                    Button("Enable …") { Task { await request() } }
                case .denied:
                    Button("Open System Settings …") {
                        IncomingNotifications.openSystemSettings()
                    }
                case .unknown, .allowed:
                    EmptyView()
                }
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        authorization = await IncomingNotifications.authorization()
    }

    private func request() async {
        do {
            _ = try await IncomingNotifications.request()
            await refresh()
        } catch {
            model.report(error)
        }
    }
}
