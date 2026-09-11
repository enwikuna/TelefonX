import Foundation
import Testing
@testable import TelefonDomain

@Suite struct AccountOrderingTests {
    @Test func legacyAccountsRemainReadableAndSortAlphabetically() throws {
        let original = PhoneAccount(name: "Zentrale", username: "z", domain: "sip.example.com")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "sortIndex")
        let legacy = try JSONDecoder().decode(
            PhoneAccount.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        #expect(legacy.sortIndex == nil)
        #expect(AccountOrdering.ordered([original, PhoneAccount(name: "Büro")]).map(\.name) == ["Büro", "Zentrale"])
    }

    @Test func explicitOrderWinsAndCanBeRenumbered() {
        let first = PhoneAccount(name: "Zentrale", sortIndex: 1)
        let second = PhoneAccount(name: "Büro", sortIndex: 0)
        let ordered = AccountOrdering.ordered([first, second])

        #expect(ordered.map(\.id) == [second.id, first.id])
        #expect(AccountOrdering.numbered([first, second]).map(\.sortIndex) == [0, 1])
    }

    @Test func duplicateOrInvalidRanksAreRejected() {
        var snapshot = AppSnapshot()
        snapshot.accounts = [PhoneAccount(name: "A", sortIndex: 0), PhoneAccount(name: "B", sortIndex: 0)]
        #expect(throws: ValidationError.invalidBackup) { try snapshot.validate() }
        snapshot.accounts[1].sortIndex = 32
        #expect(throws: ValidationError.invalidBackup) { try snapshot.validate() }
    }
}
