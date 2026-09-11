import Foundation
import TelefonDomain

enum ProAccessError: LocalizedError {
    case required
    var errorDescription: String? { L10n.text("This feature requires TelefonX Pro.") }
}

extension PhoneModel {
    var canUseReminders: Bool { purchases.access.permits(.callReminders) }
    var canUsePublicCallerLookup: Bool {
        publicCallerLookupEnabled && purchases.access.permits(.publicCallerLookup)
    }
    var permittedAccountIDs: Set<UUID> {
        let accounts = purchases.access.permits(.additionalLines)
            ? snapshot.accounts
            : Array(snapshot.accounts.prefix(1))
        return Set(accounts.map(\.id))
    }

    func isAccountLockedByPro(_ id: UUID) -> Bool {
        snapshot.accounts.contains(where: { $0.id == id }) && !permittedAccountIDs.contains(id)
    }

    func requirePro(_ feature: PaidFeature) throws {
        guard purchases.access.permits(feature) else { throw ProAccessError.required }
    }

    func effectiveRingtone(_ ringtone: LineRingtone?) -> LineRingtone {
        let selected = ringtone ?? .system(.glass)
        if case .file = selected, !purchases.access.permits(.customRingtones) { return .system(.glass) }
        return selected
    }

    func applyProAccessChange() async {
        synchronizeReminderNotifications()
        if !canUseReminders {
            preparedReminderID = nil
            reminderCalls.removeAll()
        }
        await reconcileLineAccess()
        reconcileProPresentation()
        if ready { await restoreHoldMusic() }
    }

    /// Keep every configured line, but only register the first one without Pro.
    /// Calls already in progress are deliberately allowed to finish before their
    /// now-locked line is unregistered.
    func reconcileLineAccess() async {
        let permitted = permittedAccountIDs
        if purchases.access.permits(.additionalLines),
           let defaultAccountID = snapshot.defaultAccountID,
           snapshot.accounts.contains(where: { $0.id == defaultAccountID }) {
            selectedAccountID = defaultAccountID
        } else if let selectedAccountID, !permitted.contains(selectedAccountID) {
            self.selectedAccountID = snapshot.accounts.first(where: { permitted.contains($0.id) })?.id
        }

        for account in snapshot.accounts where !permitted.contains(account.id) {
            guard !activeCalls.contains(where: { $0.accountID == account.id }) else { continue }
            cancelPendingRegistrationState(for: account.id)
            if ready { try? await engine.unregister(account.id) }
            registrations[account.id] = .disabled
        }

        guard ready else { return }
        for account in snapshot.accounts where permitted.contains(account.id) && account.enabled {
            if registrations[account.id] == .disabled {
                await register(account)
            }
        }
    }
}
