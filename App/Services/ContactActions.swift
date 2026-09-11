import Foundation
import TelefonDomain

extension PhoneModel {
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
        try commit(next)
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
        try commit(next)
    }

    func deleteHistoryRecord(_ id: UUID) throws {
        try deleteHistoryRecords([id])
    }

    func deleteHistoryRecords(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        var next = snapshot
        next.history.removeAll { ids.contains($0.id) }
        try commit(next)
        removeMissedCallBadges(for: ids)
    }

    func deleteContacts(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        var next = snapshot
        next.contacts.removeAll { ids.contains($0.id) }
        try commit(next)
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
