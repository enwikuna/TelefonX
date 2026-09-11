import Foundation
import Testing
@testable import TelefonDomain

@Suite struct DestinationTests {
    @Test(arguments: [("+49 (0) 711 / 123-45", "+4971112345"), ("tel:%2B49-711-123", "+49711123"),
                      ("**620", "**620"), ("sip:alice@EXAMPLE.COM", "sip:alice@example.com"), ("telefonx://call/071112345", "071112345")])
    func normalization(input: String, expected: String) throws { #expect(try CallDestination(input).value == expected) }
    @Test(arguments: ["", "+", "hello", "sip:a@x?Subject=bad", "sip:a@x;transport=udp", "sip:a\r\nB: x@y", "tel:12%0d%0aX", "1+23", "sip:a@@b", "sip:a@host:70000", "telefonx://call/123?auto=yes", "sip:%0D%0Aa@host", "sip:ab%xx@host"])
    func rejectsUnsafeInput(_ input: String) { #expect(throws: ValidationError.self) { try CallDestination(input) } }
    @Test func matching() throws {
        #expect(try CallDestination("0711 123456").matchingKey() == "+49711123456")
        #expect(try CallDestination("0049711123456").matchingKey() == "+49711123456")
        #expect(try CallDestination("0620").matchingKey() == "0620")
        #expect(try CallDestination("**620").matchingKey() == "**620")
    }
    @Test func SRTPNeedsTLS() {
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com", requireSRTP: true)
        #expect(throws: ValidationError.insecureMediaPolicy) { try account.validate() }
    }
    @Test func hostValidation() {
        for host in ["fritz.box", "192.168.178.1:5060", "[::1]:5061", "example.com"] { #expect(PhoneAccount.validHost(host)) }
        for host in ["http://box", "a..b", "box:0", "[::1]:99999", "box/path", "box;lr", "x\ny"] { #expect(!PhoneAccount.validHost(host)) }
    }
    @Test func newAccountHasNoVendorSpecificServer() {
        let account = PhoneAccount(name: "Leitung", username: "sipuser")
        #expect(account.domain.isEmpty)
        #expect(throws: ValidationError.invalidHost) { try account.validate() }
    }
    @Test(arguments: ["fritz.box", "sip.example.com", "192.0.2.20:5060"])
    func existingServerIsPreserved(_ server: String) throws {
        let account = PhoneAccount(name: "Leitung", username: "sipuser", domain: server)
        try account.validate()
        let data = try JSONEncoder().encode(account)
        #expect(try JSONDecoder().decode(PhoneAccount.self, from: data) == account)
    }
    @Test func secureDestination() throws {
        #expect(throws: ValidationError.insecureMediaPolicy) { try CallDestination("sips:a@example.com").uri(for: PhoneAccount()) }
    }
    @Test func remoteAddressKeepsSIPDomain() {
        #expect(CallDestination.remoteAddress(from: "Alice <sip:alice@example.com>") == "sip:alice@example.com")
        #expect(CallDestination.remoteAddress(from: "<sip:0711123456@fritz.box>") == "0711123456")
        #expect(CallDestination.remoteAddress(from: "<sip:anonymous@anonymous.invalid>") == "anonymous")
    }
}

@Suite struct CallStateTests {
    @Test func terminalStateCannotResurrect() {
        var call = CallSession(handle: CallHandle(slot: 1, generation: 1), accountID: UUID(), remote: "123", incoming: false, phase: .calling)
        let ringing = call.transition(to: .ringing), connected = call.transition(to: .connected)
        #expect(ringing); #expect(connected)
        let answer = call.answeredAt
        let regressed = call.transition(to: .ringing), repeated = call.transition(to: .connected)
        #expect(!regressed); #expect(repeated); #expect(call.answeredAt == answer)
        let ended = call.transition(to: .ended), resurrected = call.transition(to: .connected)
        #expect(ended); #expect(!resurrected)
    }
    @Test func missedVersusDeclined() {
        var call = CallSession(handle: CallHandle(slot: 2, generation: 1), accountID: UUID(), remote: "123", incoming: true, phase: .incoming)
        call.transition(to: .ended)
        #expect(CallRecord(session: call, accountName: "A").outcome == .missed)
        call.locallyDeclined = true
        #expect(CallRecord(session: call, accountName: "A").outcome == .declined)
        call.blocked = true
        #expect(CallRecord(session: call, accountName: "A").outcome == .blocked)
    }
    @Test func generationPreventsSlotCollision() { #expect(CallHandle(slot: 0, generation: 1) != CallHandle(slot: 0, generation: 2)) }
    @Test func qualityMath() {
        let quality = CallQuality(codec: "opus", clockRate: 48000, receivedPackets: 90, lostPackets: 10, jitterMilliseconds: 2, roundTripMilliseconds: 8, secureMedia: false)
        #expect(quality.lossPercent == 10)
    }
    @Test func longestAvailableRuleWins() {
        let a = UUID(), b = UUID()
        let rules = [DialRule(prefix: "0", accountID: a), DialRule(prefix: "0711", accountID: b)]
        #expect(Routing.account(for: "0711234", rules: rules, available: [a, b], fallback: a) == b)
        #expect(Routing.account(for: "0711234", rules: rules, available: [a], fallback: b) == a)
    }
    @Test func blockingNormalizes() {
        #expect(Routing.isBlocked("+49711123456", rules: [BlockRule(number: "0711123456")], anonymous: false))
        #expect(Routing.isBlocked("Anonymous", rules: [], anonymous: true))
    }
    @Test func paywallNeverInterruptsCalling() {
        let access = FeatureAccess()
        #expect(!access.permits(.additionalLines))
        #expect(access.permitsBasicCalling && access.permitsControllingActiveCalls)
        #expect(FeatureAccess(internalEvaluation: true).permits(.additionalLines))
        #expect(FeatureAccess(unlocked: [.contactImportExport]).permits(.contactImportExport))
    }
}
