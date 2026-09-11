import Foundation
import Testing
@testable import TelefonDomain

@Suite struct SoundTests {
    @Test func oldAccountsAndPreferencesDecodeWithoutSoundFields() throws {
        var account = PhoneAccount(name: "Privat", username: "user", domain: "sip.example.com", proxy: "proxy.example.com", useICE: true)
        account.ringtone = .system(.ping)
        var data = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(account)) as? [String: Any])
        data.removeValue(forKey: "ringtone")
        data.removeValue(forKey: "suppressCallerID")
        let decoded = try JSONDecoder().decode(PhoneAccount.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(decoded.ringtone == nil)
        #expect(!decoded.suppressCallerID)
        #expect(decoded.proxy == account.proxy && decoded.useICE)
        var snapshot = AppSnapshot(); snapshot.holdMusic = AudioAsset(name: "Musik")
        var metadata = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        metadata.removeValue(forKey: "holdMusic")
        #expect(try JSONDecoder().decode(AppSnapshot.self, from: JSONSerialization.data(withJSONObject: metadata)).holdMusic == nil)
    }

    @Test func soundPreferencesRoundtripWithoutAbsolutePaths() throws {
        var account = PhoneAccount(name: "Büro", username: "user", domain: "sip.example.com", suppressCallerID: true)
        account.ringtone = .file(AudioAsset(name: "Mein Klingelton"))
        var snapshot = AppSnapshot(); snapshot.accounts = [account]; snapshot.holdMusic = AudioAsset(name: "Wartemusik")
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(AppSnapshot.self, from: data) == snapshot)
        #expect(!String(decoding: data, as: UTF8.self).contains("/Users/"))
        try snapshot.validate()
    }

    @Test func ringingUsesEachLineAndSkipsAnsweredOrBlockedCalls() {
        var a = PhoneAccount(), b = PhoneAccount()
        a.ringtone = .system(.ping); b.ringtone = .system(.hero)
        var first = CallSession(handle: CallHandle(slot: 0, generation: 1), accountID: a.id, remote: "101", incoming: true, phase: .incoming, startedAt: Date(timeIntervalSince1970: 1))
        let second = CallSession(handle: CallHandle(slot: 1, generation: 1), accountID: b.id, remote: "102", incoming: true, phase: .ringing, startedAt: Date(timeIntervalSince1970: 2))
        #expect(RingtoneRouting.incoming(in: [second, first])?.id == first.id)
        #expect(RingtoneRouting.sound(for: first, accounts: [a, b]) == .system(.ping))
        #expect(RingtoneRouting.sound(for: second, accounts: [a, b]) == .system(.hero))
        first.blocked = true
        #expect(RingtoneRouting.incoming(in: [first, second])?.id == second.id)
        first.blocked = false; first.answeredAt = Date()
        #expect(RingtoneRouting.incoming(in: [first]) == nil)
        #expect(RingtoneRouting.sound(for: first, accounts: []) == .system(.glass))
    }

    @Test func editingRingtonePreservesProviderOverrides() {
        let original = PhoneAccount(name: "Privat", username: "user", authenticationName: "auth", domain: "sip.example.com",
                                    registrar: "reg.example.com", proxy: "proxy.example.com", transport: .tls,
                                    requireSRTP: true, useICE: true, g711Only: true, registrationInterval: 600)
        var edited = original; edited.ringtone = .system(.funk)
        edited.ringtone = nil
        #expect(edited == original)
    }
}
