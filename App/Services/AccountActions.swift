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
        let previousAccounts = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0) })
        let changedAccountIDs = Set(next.accounts.lazy.filter { previousAccounts[$0.id] != $0 }.map(\.id))
        do {
            try commit(next, changes: SnapshotChanges(accounts: .identifiers(changedAccountIDs), preferences: true))
        }
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
        let affectedContactIDs = Set(next.contacts.lazy.filter { $0.preferredAccountID == id }.map(\.id))
        for index in next.contacts.indices where next.contacts[index].preferredAccountID == id { next.contacts[index].preferredAccountID = nil }
        if next.defaultAccountID == id { next.defaultAccountID = next.accounts.first?.id }
        let previousAccounts = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0) })
        var changedAccountIDs = Set(next.accounts.lazy.filter { previousAccounts[$0.id] != $0 }.map(\.id))
        changedAccountIDs.insert(id)
        try commit(next, changes: SnapshotChanges(accounts: .identifiers(changedAccountIDs),
                                                  contacts: .identifiers(affectedContactIDs),
                                                  preferences: true))
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
        do { try commit(next, changes: SnapshotChanges(accounts: .all)) } catch { report(error) }
        Task { await applyProAccessChange() }
    }
    func moveAccount(_ id: UUID, by offset: Int) {
        guard let index = snapshot.accounts.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard snapshot.accounts.indices.contains(destination) else { return }
        var next = snapshot
        next.accounts.swapAt(index, destination)
        next.accounts = AccountOrdering.numbered(next.accounts)
        do { try commit(next, changes: SnapshotChanges(accounts: .all)) } catch { report(error) }
        Task { await applyProAccessChange() }
    }
}
