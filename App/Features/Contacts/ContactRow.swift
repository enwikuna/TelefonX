import SwiftUI
import TelefonDomain

struct ContactRow: View {
    @Environment(PhoneModel.self) private var model
    let contact: PhoneContact
    let favoritesOnly: Bool
    let selected: Bool
    let selectionCount: Int
    let requestAction: (ContactActionRequest) -> Void
    let edit: () -> Void
    let selectedLocalContacts: [PhoneContact]

    private var status: ContactBlockStatus { .resolve(contact, rules: model.snapshot.blocks) }
    private var displayedNumber: String {
        ((favoritesOnly || contact.favorite) ? ContactFavorites.number(for: contact) : contact.numbers.first) ?? ""
    }
    private var detail: String {
        [contact.company, displayedNumber, contact.group].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: HistoryRowLayout.avatarTextSpacing) {
            ContactAvatar(contact: contact)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(contact.name).font(.body.weight(.medium)).lineLimit(1)
                    if contact.favorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).accessibilityLabel("Favorite")
                    }
                    if status.hasBlockedNumbers {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                            .accessibilityLabel(status.label).help(status.label)
                    }
                }
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                callControl
                Button(action: edit) { RowActionIcon(systemName: "info.circle", tint: .secondary) }
                    .buttonBorderShape(.circle).telefonButtonStyle().help("Edit Contact …")
                    .accessibilityLabel("Edit Contact …")
                    .accessibilityIdentifier("contact-info")
            }
        }
        .padding(.horizontal, HistoryRowLayout.contentHorizontalInset)
        .frame(height: ContactTable.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: HistoryRowLayout.selectionCornerRadius)
                    .fill(Color.primary.opacity(0.08))
                    .padding(.horizontal, HistoryRowLayout.selectionHorizontalInset)
                    .padding(.vertical, HistoryRowLayout.selectionVerticalInset)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, HistoryRowLayout.nativeSelectionSurfaceHorizontalInset)
        .contextMenu {
            if selected && selectionCount > 1 {
                if !selectedLocalContacts.isEmpty {
                    let newFavorites = selectedLocalContacts.filter { !$0.favorite }
                    let blockable = selectedLocalContacts.filter {
                        ContactBlockStatus.resolve($0, rules: model.snapshot.blocks).canBlockMore
                    }
                    Button(L10n.format(newFavorites.count == 1 ? "Add %lld Contact to Favorites" : "Add %lld Contacts to Favorites",
                                       Int64(newFavorites.count)), systemImage: "star") {
                        do { try model.addContactsToFavorites(Set(newFavorites.map(\.id))) }
                        catch { model.report(error) }
                    }
                    .disabled(newFavorites.isEmpty)
                    Button(L10n.format(blockable.count == 1 ? "Block %lld Contact …" : "Block %lld Contacts …",
                                       Int64(blockable.count)), systemImage: "hand.raised") {
                        requestAction(.init(blocking: blockable))
                    }
                    .disabled(blockable.isEmpty)
                    let blocked = selectedLocalContacts.filter {
                        ContactBlockStatus.resolve($0, rules: model.snapshot.blocks).hasBlockedNumbers
                    }
                    if !blocked.isEmpty {
                        Button(L10n.format(blocked.count == 1 ? "Unblock %lld Contact" : "Unblock %lld Contacts",
                                           Int64(blocked.count)), systemImage: "hand.raised.slash") {
                            model.unblock(blocked.flatMap(\.numbers))
                        }
                    }
                    Divider()
                    Button("Delete \(selectionCount) Contacts …", systemImage: "trash", role: .destructive) {
                        requestAction(.init(deleting: selectedLocalContacts))
                    }
                }
            } else {
                Button("Edit …", systemImage: "pencil", action: edit)
                Button(contact.favorite ? "Remove from Favorites" : "Add to Favorites",
                       systemImage: contact.favorite ? "star.slash" : "star") { toggleFavorite() }
                Button(status.canBlockMore ? "Block Contact …" : "Contact Already Blocked",
                       systemImage: "hand.raised") { requestAction(.init(kind: .block, contact: contact)) }
                    .disabled(!status.canBlockMore)
                if status.hasBlockedNumbers {
                    Button("Unblock", systemImage: "hand.raised.slash") {
                        model.unblock(contact.numbers)
                    }
                }
                Divider()
                Button("Delete Contact …", systemImage: "trash", role: .destructive) {
                    requestAction(.init(kind: .delete, contact: contact))
                }
            }
        }
    }

    @ViewBuilder private var callControl: some View {
        if requiresNumberSelection {
            Menu {
                ForEach(contact.numbers, id: \.self) { number in
                    Button(number) { performCall(number) }
                }
            } label: {
                RowActionIcon(systemName: "phone.fill")
            }
            .telefonRowActionMenuStyle()
            .help("Choose Number")
            .accessibilityLabel(L10n.format("%@, Choose Number", contact.name))
        } else {
            Button {
                if !displayedNumber.isEmpty { performCall(displayedNumber) }
            } label: {
                RowActionIcon(systemName: "phone.fill")
            }
            .buttonBorderShape(.circle)
            .telefonButtonStyle()
            .disabled(displayedNumber.isEmpty)
            .help(listCallActionTitle)
            .accessibilityLabel(L10n.format("%@, %@", contact.name,
                                            listCallActionTitle))
        }
    }

    private var requiresNumberSelection: Bool {
        !favoritesOnly && contact.numbers.count > 1
    }

    private var listCallActionTitle: String {
        if !model.activeCalls.isEmpty { return L10n.text("Start Consultation") }
        if model.automaticallyStartListCalls { return L10n.text("Place Call") }
        return L10n.text(favoritesOnly ? "Use Favorite Number" : "Use Number")
    }

    private func performCall(_ number: String) {
        Task { await model.performListCall(number, preferredAccountID: contact.preferredAccountID) }
    }

    private func toggleFavorite() {
        var changed = contact
        changed.favorite.toggle()
        do { try model.saveContact(changed) } catch { model.report(error) }
    }
}
