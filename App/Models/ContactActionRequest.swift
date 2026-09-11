import TelefonDomain

struct ContactActionRequest: Identifiable {
    enum Kind: String { case block, delete }
    let kind: Kind
    let contacts: [PhoneContact]

    init(kind: Kind, contact: PhoneContact) {
        self.kind = kind
        contacts = [contact]
    }

    init(deleting contacts: [PhoneContact]) {
        kind = .delete
        self.contacts = contacts
    }

    init(blocking contacts: [PhoneContact]) {
        kind = .block
        self.contacts = contacts
    }

    var contact: PhoneContact { contacts[0] }

    var id: String { "\(kind.rawValue)-\(contacts.map(\.id.uuidString).sorted().joined(separator: ","))" }
    var title: String {
        kind == .delete
            ? (contacts.count == 1 ? L10n.text("Delete Contact?") : L10n.format("Delete %lld Contacts?", Int64(contacts.count)))
            : (contacts.count == 1 ? L10n.text("Block Contact?") : L10n.format("Block %lld Contacts?", Int64(contacts.count)))
    }
    var button: String {
        kind == .delete
            ? (contacts.count == 1 ? L10n.text("Delete") : L10n.format("Delete %lld", Int64(contacts.count)))
            : (contacts.count == 1 ? L10n.text("Block Contact") : L10n.format("Block %lld Contacts", Int64(contacts.count)))
    }
    var message: String {
        if kind == .delete {
            contacts.count == 1
                ? L10n.format("The local contact %@ will be deleted. Recents and existing blocks are retained.", contact.name)
                : L10n.format("The %lld selected local contacts will be deleted. Recents and existing blocks are retained.", Int64(contacts.count))
        } else if contacts.count > 1 {
            L10n.format("All phone numbers of the %lld selected contacts will be blocked on every line. The contacts remain in your address book. You can remove the blocks under Settings → Rules.", Int64(contacts.count))
        } else {
            L10n.format("All phone numbers saved for %@ will be blocked on every line. The contact remains in your address book. You can remove the blocks under Settings → Rules.", contact.name)
        }
    }
}
