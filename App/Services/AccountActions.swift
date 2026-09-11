import Foundation
import TelefonDomain

extension PhoneModel {
    func saveAccount(_ account: PhoneAccount, password: String) async throws {
        let existing = snapshot.accounts.first { $0.id == account.id }
        if existing == nil && !snapshot.accounts.isEmpty { try requirePro(.additionalLines) }
        if existing != nil && isAccountLockedByPro(account.id) { try requirePro(.additionalLines) }
        if case .file = account.ringtone, account.ringtone != existing?.ringtone {
            try requirePro(.customRingtones)
        }
        guard activeCalls.isEmpty, !callOperationPending, !configurationBusy else { throw AppError.callInProgress }
        configurationBusy = true; defer { configurationBusy = false }
        try account.validate()
        guard account.stunServer.isEmpty else { throw AppError.unsupportedSTUN }
        let previousPassword = try credentials.password(for: account.id)
        let effective = password.isEmpty ? previousPassword : password
        guard let effective, !effective.isEmpty else { throw AppError.missingPassword }
        try credentials.setPassword(effective, for: account.id)
        var next = snapshot
        if let index = next.accounts.firstIndex(where: { $0.id == account.id }) {
            var account = account
            account.sortIndex = next.accounts[index].sortIndex
            next.accounts[index] = account
        } else {
            var accounts = AccountOrdering.numbered(next.accounts)
            var account = account
            account.sortIndex = accounts.count
            accounts.append(account)
            next.accounts = accounts
        }
        if next.defaultAccountID == nil { next.defaultAccountID = account.id }
        do { try commit(next) }
        catch {
            if let previousPassword { try? credentials.setPassword(previousPassword, for: account.id) }
            else { try? credentials.deletePassword(for: account.id) }
            throw error
        }
        if selectedAccountID == nil { selectedAccountID = account.id }
        if ready { try await engine.unregister(account.id); await register(account) }
    }
    func deleteAccount(_ id: UUID) async throws {
        guard activeCalls.isEmpty, !callOperationPending, !configurationBusy else { throw AppError.callInProgress }
        configurationBusy = true; defer { configurationBusy = false }
        var next = snapshot
        next.accounts.removeAll { $0.id == id }
        next.accounts = AccountOrdering.numbered(next.accounts)
        next.dialRules.removeAll { $0.accountID == id }
        for index in next.contacts.indices where next.contacts[index].preferredAccountID == id { next.contacts[index].preferredAccountID = nil }
        if next.defaultAccountID == id { next.defaultAccountID = next.accounts.first?.id }
        try commit(next)
        if selectedAccountID == id { selectedAccountID = next.defaultAccountID }
        if ready { try await engine.unregister(id) }
        try credentials.deletePassword(for: id); registrations.removeValue(forKey: id)
        await reconcileLineAccess()
    }
    func moveAccount(_ sourceID: UUID, over targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = snapshot.accounts.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = snapshot.accounts.firstIndex(where: { $0.id == targetID }) else { return }
        var next = snapshot
        let account = next.accounts.remove(at: sourceIndex)
        next.accounts.insert(account, at: targetIndex)
        next.accounts = AccountOrdering.numbered(next.accounts)
        do { try commit(next) } catch { report(error) }
        Task { await applyProAccessChange() }
    }
    func moveAccount(_ id: UUID, by offset: Int) {
        guard let index = snapshot.accounts.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard snapshot.accounts.indices.contains(destination) else { return }
        var next = snapshot
        next.accounts.swapAt(index, destination)
        next.accounts = AccountOrdering.numbered(next.accounts)
        do { try commit(next) } catch { report(error) }
        Task { await applyProAccessChange() }
    }
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
        try commit(next)
    }
    func block(_ number: String) {
        block([number])
    }
    func block(_ numbers: [String]) {
        do {
            var next = snapshot
            var keys = Set(next.blocks.compactMap { try? CallDestination($0.number).matchingKey() })
            for number in numbers {
                guard let value = try? CallDestination(number), keys.insert(value.matchingKey()).inserted else { continue }
                next.blocks.append(BlockRule(number: value.value))
            }
            guard next.blocks != snapshot.blocks else { return }
            try commit(next)
        } catch { report(error) }
    }
    func unblock(_ number: String) {
        unblock([number])
    }
    func unblock(_ numbers: [String]) {
        do {
            let keys = Set(numbers.compactMap { try? CallDestination($0).matchingKey() })
            guard !keys.isEmpty else { return }
            var next = snapshot
            next.blocks.removeAll { rule in
                guard let key = try? CallDestination(rule.number).matchingKey() else { return false }
                return keys.contains(key)
            }
            guard next.blocks != snapshot.blocks else { return }
            try commit(next)
        } catch { report(error) }
    }
}
