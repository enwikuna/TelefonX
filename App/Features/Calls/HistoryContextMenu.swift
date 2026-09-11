import SwiftUI
import TelefonDomain

struct HistoryContextMenu: View {
    @Environment(PhoneModel.self) private var model
    let record: CallRecord
    let hasDestination: Bool
    let isBlocked: Bool
    let editContact: (PhoneContact) -> Void
    let addToContact: () -> Void
    let scheduleReminder: () -> Void
    let toggleBlock: () -> Void
    let delete: () -> Void

    private var accountID: UUID? { model.snapshot.accounts.contains(where: { $0.id == record.accountID }) ? record.accountID : nil }

    var body: some View {
        Button("Place Call", systemImage: "phone") { Task { await model.callNumber(record.remote, preferredAccountID: accountID) } }
            .disabled(!model.canCall(record.remote, preferredAccountID: accountID))
        Button("Copy Number", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.remote, forType: .string)
        }.disabled(!hasDestination)
        if let contact = model.contact(for: record.remote) {
            Button("Edit Contact …", systemImage: "person.crop.circle") { editContact(contact) }
        } else {
            Button("Create New Contact …", systemImage: "person.crop.circle.badge.plus") {
                editContact(HistoryPresentation.contactDraft(number: record.remote,
                                                              displayName: model.displayName(record.remote)))
            }.disabled(!hasDestination)
        }
        Button("Add to Contact …", systemImage: "person.crop.circle.badge.plus", action: addToContact)
            .disabled(!hasDestination || model.snapshot.contacts.isEmpty)
        if model.canUseReminders {
            Button("Schedule Callback …", systemImage: "calendar.badge.clock", action: scheduleReminder)
                .disabled(!hasDestination)
        } else {
            ProAccessButton("Plan Callbacks with TelefonX Pro …")
        }
        Button(isBlocked ? "Unblock …" : "Block Number …",
               systemImage: isBlocked ? "hand.raised.slash" : "hand.raised",
               action: toggleBlock)
            .disabled(!hasDestination)
        Divider()
        Button("Delete …", systemImage: "trash", role: .destructive, action: delete)
    }
}
