import Foundation
import Testing
import TelefonDomain
import TelefonData

@Suite struct FavoritesTests {
    @Test func legacyFavoritesDecodeAndHaveDeterministicOrder() throws {
        let contacts = [PhoneContact(name: "Sam", numbers: ["102"], favorite: true),
                        PhoneContact(name: "Alex", numbers: ["101"], favorite: true)]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(contacts)) as? [[String: Any]])
        for index in json.indices {
            json[index].removeValue(forKey: "favoriteOrder"); json[index].removeValue(forKey: "favoriteNumber")
        }
        let legacy = try JSONDecoder().decode([PhoneContact].self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy == contacts)
        #expect(ContactFavorites.ordered(legacy).map(\.name) == ["Alex", "Sam"])
        #expect(ContactFavorites.choices(legacy).map(\.number) == ["101", "102"])
    }

    @Test func preferredNumberUsesCurrentSpellingAndFallsBackAfterRemoval() {
        var contact = PhoneContact(name: "Alex", numbers: ["101", "0711 1234567"], favorite: true, favoriteNumber: "+497111234567")
        #expect(ContactFavorites.number(for: contact) == "0711 1234567")
        contact.numbers = ["101"]
        #expect(ContactFavorites.number(for: contact) == "101")
        contact.numbers = []
        #expect(ContactFavorites.number(for: contact) == nil)
        #expect(!ContactFavorites.equivalent("anonymous", "anonymous"))
    }

    @Test @MainActor func favoriteNumberAndOrderSurviveBackupAndDatabaseReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TelefonX-favorites-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var snapshot = AppSnapshot()
        snapshot.contacts = [PhoneContact(name: "Alex", numbers: ["101", "201"], favorite: true, favoriteNumber: "201", favoriteOrder: 1),
                             PhoneContact(name: "Sam", numbers: ["102"], favorite: true, favoriteNumber: "102", favoriteOrder: 0)]
        #expect(try BackupCodec.decode(BackupCodec.encode(snapshot)) == snapshot)
        let url = folder.appending(path: "store")
        do { let repository = try SwiftDataRepository(url: url); try repository.save(snapshot) }
        let reopened = try SwiftDataRepository(url: url).load()
        #expect(reopened == snapshot)
        #expect(ContactFavorites.choices(reopened.contacts).map(\.number) == ["102", "201"])
        snapshot.contacts[0].favoriteOrder = -1
        #expect(throws: ValidationError.invalidBackup) { try snapshot.validate() }
        snapshot.contacts[0].favoriteOrder = 0; snapshot.contacts[0].favoriteNumber = "anonymous"
        #expect(throws: (any Error).self) { try snapshot.validate() }
    }
}
