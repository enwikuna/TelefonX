import Foundation
import Testing
import TelefonDomain
@testable import TelefonData

@Suite struct DataTests {
    @Test func reminderExportPreservesNotesDatesAndCompletionAndEscapesFormulas() {
        var reminder = CallReminder(name: "=SUM(A1)", number: "+49123", note: "Angebot, Teil 1\n\"Zitat\"",
                                    dueAt: Date(timeIntervalSince1970: 0))
        reminder.completedAt = Date(timeIntervalSince1970: 60)
        let csv = RemindersCSV.encode([reminder])
        #expect(csv.contains("'=SUM(A1)"))
        #expect(csv.contains("'+49123"))
        #expect(csv.contains("\"Angebot, Teil 1\n\"\"Zitat\"\"\""))
        #expect(csv.contains("1970-01-01T00:00:00Z"))
        #expect(csv.contains("\"Erledigt\",\"1970-01-01T00:01:00Z\""))
        #expect(RemindersCSV.encode([]) == "\"Name\",\"Telefon\",\"Termin\",\"Notizen\",\"Status\",\"Erledigt am\"")
    }

    @Test func CSVMultilineAndFormulaSafety() throws {
        let contact = PhoneContact(name: "=SUM(A1)", company: "Firma, GmbH", numbers: ["+4971112345", "**620"], notes: "Zeile 1\n\"Zitat\"", group: "Büro")
        let csv = ContactsCSV.encode([contact])
        #expect(csv.contains("'=SUM")); #expect(csv.contains("'+497"))
        let imported = try ContactsCSV.decode(csv)
        #expect(imported.count == 1); #expect(imported[0].name == contact.name)
        #expect(imported[0].numbers == contact.numbers); #expect(imported[0].notes == contact.notes)
    }
    @Test func CSVFileRoundtripPreserves300ContactsAndAllExportedFields() throws {
        let contacts = (0..<300).map { index in
            PhoneContact(name: "Jörg Müller \(index)", company: "Büro; \"Nord, Süd\"",
                         numbers: ["+4930\(100000 + index)", "00\(200000 + index)"],
                         email: "kontakt\(index)@example.com", notes: "Erste Zeile\nRückruf: Grüße!",
                         group: "Vertrieb Österreich", phoneNumberLabels: [.work, .mobile])
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "TelefonX-CSV-test-\(UUID()).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(ContactsCSV.encode(contacts).utf8).write(to: url, options: .atomic)
        let imported = try ContactsCSV.decode(String(contentsOf: url, encoding: .utf8))
        #expect(imported.count == 300)
        #expect(Set(imported.map(\.id)).count == 300)
        for (original, restored) in zip(contacts, imported) {
            #expect(restored.name == original.name)
            #expect(restored.company == original.company)
            #expect(restored.phoneNumbers == original.phoneNumbers)
            #expect(restored.email == original.email)
            #expect(restored.notes == original.notes)
            #expect(restored.group == original.group)
        }
    }

    @Test func CSVAcceptsBOMAndRejectsMissingRequiredFields() throws {
        let imported = try ContactsCSV.decode("\u{feff}Name;Telefon;Firma\r\nJörg;00123;Büro\r\n")
        #expect(imported.first?.name == "Jörg")
        #expect(imported.first?.numbers == ["00123"])
        #expect(try ContactsCSV.decode(ContactsCSV.encode([])).isEmpty)
        for invalid in ["Name,Firma\nAda,Test", "Name,Telefon\n,123", "Name,Telefon\nAda,"] {
            #expect(throws: (any Error).self) { try ContactsCSV.decode(invalid) }
        }
    }

    @Test func CSVSemicolon() throws {
        let contacts = try ContactsCSV.decode("Name;Telefon;Firma\r\nAda;071123456;Beispiel\r\n")
        #expect(contacts.count == 1); #expect(contacts[0].company == "Beispiel")
        #expect(contacts[0].phoneNumbers == [ContactPhoneNumber(value: "071123456", label: .other)])
    }
    @Test func phoneLabelsSurviveBackupAndCSVWhileLegacyContactsStayReadable() throws {
        let contact = PhoneContact(name: "Ada", numbers: ["101", "071123456"],
                                   phoneNumberLabels: [.work, .mobile])
        let data = try JSONEncoder().encode(contact)
        #expect(try JSONDecoder().decode(PhoneContact.self, from: data) == contact)
        #expect(try ContactsCSV.decode(ContactsCSV.encode([contact]))[0].phoneNumbers == contact.phoneNumbers)

        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "phoneNumberLabels")
        let decoded = try JSONDecoder().decode(PhoneContact.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.numbers == contact.numbers)
        #expect(decoded.phoneNumbers.map(\.label) == [.other, .other])
    }
    @Test(arguments: ["'t Hooft", "'=literal", "  =formula", "\t=tabbed", "Ada"])
    func CSVNamesStayExact(_ name: String) throws {
        let contact = PhoneContact(name: name, numbers: ["123"])
        #expect(try ContactsCSV.decode(ContactsCSV.encode([contact]))[0].name == name)
    }
    @Test func CSVInvalidIsAtomic() {
        #expect(throws: (any Error).self) { try ContactsCSV.decode("Name,Telefon\nValid,123\nBad,not-a-number") }
        #expect(throws: (any Error).self) { try ContactsCSV.decode("Name,Telefon\n\"Unclosed,123") }
    }
    @Test func backupRoundtripWithoutCredentials() throws {
        var state = AppSnapshot()
        let account = PhoneAccount(name: "Test", username: "user", domain: "sip.example.com")
        state.accounts = [account]; state.defaultAccountID = account.id
        state.contacts = [PhoneContact(name: "Ada", numbers: ["123"], notes: "Privat")]
        let data = try BackupCodec.encode(state)
        #expect(try BackupCodec.decode(data) == state)
        #expect(!String(decoding: data, as: UTF8.self).lowercased().contains("password"))
    }
    @Test func remindersRoundtripAndLegacySnapshotsRemainReadable() throws {
        var state = AppSnapshot()
        state.reminders = [CallReminder(name: "Ada", number: "123", note: "Angebot",
                                        dueAt: Date(timeIntervalSince1970: 200_000),
                                        createdAt: Date(timeIntervalSince1970: 100_000))]
        let data = try BackupCodec.encode(state)
        #expect(try BackupCodec.decode(data).reminders == state.reminders)

        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "reminders")
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.reminders.isEmpty)
    }
    @Test func rejectsDuplicatesAndNewerSchema() throws {
        var state = AppSnapshot(); let contact = PhoneContact(name: "A", numbers: ["123"])
        state.contacts = [contact, contact]
        #expect(throws: ValidationError.invalidBackup) { try state.validate() }
        state = AppSnapshot(); state.schemaVersion = 2
        #expect(throws: ValidationError.unsupportedVersion) { try state.validate() }
        state = AppSnapshot()
        let reminder = CallReminder(name: "Ada", number: "123", dueAt: Date())
        state.reminders = [reminder, reminder]
        #expect(throws: ValidationError.invalidBackup) { try state.validate() }
    }
    @MainActor @Test func persistenceReopenUpdateDelete() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TelefonX-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store")
        var state = AppSnapshot(); let contact = PhoneContact(name: "Ada", numbers: ["123"])
        state.contacts = [contact]
        do { let repo = try SwiftDataRepository(url: url); try repo.save(state) }
        let repo = try SwiftDataRepository(url: url)
        #expect(try repo.load() == state)
        state.contacts[0].notes = "Neue Notiz"; try repo.save(state)
        #expect(try repo.load().contacts[0].notes == "Neue Notiz")
        state.reminders = [CallReminder(name: "Ada", number: "123", note: "Rückfrage",
                                        dueAt: Date().addingTimeInterval(3600))]
        try repo.save(state)
        #expect(try repo.load().reminders == state.reminders)
        var invalid = state; invalid.contacts.append(contact)
        #expect(throws: ValidationError.invalidBackup) { try repo.save(invalid) }
        #expect(try repo.load() == state)
        state.contacts = []; try repo.save(state)
        #expect(try repo.load().contacts.isEmpty)
    }
    @MainActor @Test func accountOrderSurvivesDatabaseReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TelefonX-order-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store")
        let first = PhoneAccount(name: "Zentrale", username: "z", domain: "sip.example.com", sortIndex: 0)
        let second = PhoneAccount(name: "Büro", username: "b", domain: "sip.example.com", sortIndex: 1)
        var state = AppSnapshot()
        state.accounts = [first, second]

        do { let repository = try SwiftDataRepository(url: url); try repository.save(state) }
        let reopened = try SwiftDataRepository(url: url).load()

        #expect(reopened.accounts.map(\.id) == [first.id, second.id])
        #expect(reopened.accounts.map(\.sortIndex) == [0, 1])
    }
}
