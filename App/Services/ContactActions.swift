import Foundation
import TelefonDomain

extension PhoneModel {
    func saveContact(_ contact: PhoneContact) throws {
        var contact = contact
        var next = snapshot
        let previous = snapshot.contacts.first { $0.id == contact.id }
        if contact.favorite {
            contact.favoriteNumber = ContactFavorites.number(for: contact)
            if previous?.favorite != true {
                let ordered = ContactFavorites.ordered(snapshot.contacts).filter { $0.id != contact.id }
                let ranks = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
                for index in next.contacts.indices where next.contacts[index].favorite {
                    next.contacts[index].favoriteOrder = ranks[next.contacts[index].id]
                }
                contact.favoriteOrder = ordered.count
            }
        } else { contact.favoriteNumber = nil; contact.favoriteOrder = nil }
        if let index = next.contacts.firstIndex(where: { $0.id == contact.id }) { next.contacts[index] = contact }
        else { next.contacts.append(contact) }
        let previousContacts = Dictionary(uniqueKeysWithValues: snapshot.contacts.map { ($0.id, $0) })
        let changedIDs = Set(next.contacts.lazy.filter { previousContacts[$0.id] != $0 }.map(\.id))
        try commit(next, changes: SnapshotChanges(contacts: .identifiers(changedIDs)))
    }

    func addContactsToFavorites(_ ids: Set<UUID>) throws {
        let additions = snapshot.contacts.filter { ids.contains($0.id) && !$0.favorite }
        guard !additions.isEmpty else { return }
        let contacts = ContactFavorites.ordered(snapshot.contacts) + additions
        try saveFavorites(contacts.map { FavoriteChoice(id: $0.id, number: ContactFavorites.number(for: $0)) })
    }

    func saveFavorites(_ choices: [FavoriteChoice]) throws {
        guard Set(choices.map(\.id)).count == choices.count else { throw ContactActionError.changed }
        for choice in choices {
            guard let contact = snapshot.contacts.first(where: { $0.id == choice.id }) else { throw ContactActionError.changed }
            if let number = choice.number {
                guard contact.numbers.contains(where: { ContactFavorites.equivalent($0, number) }) else { throw ContactActionError.changed }
            } else if !contact.numbers.isEmpty { throw ContactActionError.changed }
        }
        var next = snapshot
        let positions = Dictionary(uniqueKeysWithValues: choices.enumerated().map { ($0.element.id, $0.offset) })
        for index in next.contacts.indices {
            let position = positions[next.contacts[index].id]
            next.contacts[index].favorite = position != nil
            next.contacts[index].favoriteOrder = position
            next.contacts[index].favoriteNumber = position.flatMap { choices[$0].number }
        }
        let previousContacts = Dictionary(uniqueKeysWithValues: snapshot.contacts.map { ($0.id, $0) })
        let changedIDs = Set(next.contacts.lazy.filter { previousContacts[$0.id] != $0 }.map(\.id))
        try commit(next, changes: SnapshotChanges(contacts: .identifiers(changedIDs)))
    }

    func addNumber(_ raw: String, to contactID: UUID) throws {
        let number = try CallDestination(raw).value
        var next = snapshot
        guard let index = next.contacts.firstIndex(where: { $0.id == contactID }) else { throw ContactActionError.changed }
        if next.contacts[index].numbers.contains(where: { ContactFavorites.equivalent($0, number) }) { return }
        guard next.contacts[index].numbers.count < 20 else { throw ContactActionError.tooManyNumbers }
        var entries = next.contacts[index].phoneNumbers
        entries.append(ContactPhoneNumber(value: number, label: .other))
        next.contacts[index].phoneNumbers = entries
        try commit(next, changes: SnapshotChanges(contacts: .identifiers([contactID])))
    }

    func deleteHistoryRecords(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        var next = snapshot
        next.history.removeAll { ids.contains($0.id) }
        try commit(next, changes: SnapshotChanges(history: .identifiers(ids)))
        removeMissedCallBadges(for: ids)
    }

    func deleteContacts(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        var next = snapshot
        next.contacts.removeAll { ids.contains($0.id) }
        try commit(next, changes: SnapshotChanges(contacts: .identifiers(ids)))
    }
}

enum ContactActionError: LocalizedError {
    case changed, tooManyNumbers
    var errorDescription: String? {
        switch self {
        case .changed: L10n.text("A contact has since been changed or removed. Open the selection again.")
        case .tooManyNumbers: L10n.text("This contact already has 20 phone numbers.")
        }
    }
}
