import Testing
import TelefonDomain
@testable import TelefonX

@Suite struct LineStatusPresentationTests {
    @Test func noAccountsAndDisabledLineAreInactive() {
        #expect(LineStatusPresentation.noAccounts.title == "No Line Configured")
        #expect(LineStatusPresentation.noAccounts.level == .inactive)
        let status = LineStatusPresentation(account: PhoneAccount(name: "Home", enabled: false), state: .disabled)
        #expect(status.title == "Home")
        #expect(status.accessibilityTitle == "Home, Disabled")
        #expect(status.level == .inactive)
    }

    @Test func oneConnectedLineUsesHealthyStatus() {
        let status = LineStatusPresentation(account: PhoneAccount(name: "Enwikuna"), state: .registered)
        #expect(status.title == "Enwikuna")
        #expect(status.accessibilityTitle == "Enwikuna, Connected")
        #expect(status.level == .connected)
    }

    @Test func connectingLineUsesOrangeIndividualStatus() {
        let status = LineStatusPresentation(account: PhoneAccount(name: "Gmelin Immobilien"), state: .registering)
        #expect(status.title.count <= 30)
        #expect(status.title == "Gmelin Immobilien")
        #expect(status.accessibilityTitle == "Gmelin Immobilien, Connecting …")
        #expect(status.level == .connecting)
    }

    @Test func unavailableLineKeepsFullNameForAccessibility() {
        let account = PhoneAccount(name: "Very Long Business Telephone Line")
        let unavailable = LineStatusPresentation(account: account, state: .failed(408))
        #expect(unavailable.title.count <= 30)
        #expect(unavailable.title == "Very Long Business Telephone …")
        #expect(unavailable.accessibilityTitle == "Very Long Business Telephone Line, Disconnected")
        #expect(unavailable.level == .unavailable)
    }
}
