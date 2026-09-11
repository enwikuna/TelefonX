import Testing
@testable import TelefonX

@Suite struct PublicCallerLookupTests {
    @Test func normalizesSupportedPhoneNumberSpellings() {
        let expected = "+49374574447100"
        #expect(PublicCallerNumbers.normalized("+49-3745-74447-100") == expected)
        #expect(PublicCallerNumbers.normalized("+49 3745 74447 100") == expected)
        #expect(PublicCallerNumbers.normalized("0049 3745 74447 100") == expected)
        #expect(PublicCallerNumbers.normalized("sip:101@example.com") == nil)
        #expect(PublicCallerNumbers.normalized("anonymous") == nil)
    }

    @Test func derivesConservativeGermanSwitchboardCandidates() {
        let number = "+49374574447100"
        let candidates = PublicCallerNumbers.lookupCandidates(for: number)
        #expect(candidates.first == number)
        #expect(candidates.contains("+493745744470"))
        #expect(PublicCallerNumbers.isPlausibleSwitchboard(original: number, matched: "+493745744470"))
        #expect(!PublicCallerNumbers.isPlausibleSwitchboard(original: number, matched: "+493745744480"))
    }

    @Test func doesNotDeriveSwitchboardsForMobileOrShortNumbers() {
        #expect(PublicCallerNumbers.lookupCandidates(for: "+491701234567") == ["+491701234567"])
        #expect(PublicCallerNumbers.lookupCandidates(for: "101").isEmpty)
    }
}
