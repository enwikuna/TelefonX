import Foundation
import SwiftData
import TelefonDomain

/// Storage DTOs are versioned independently of domain types. Each entity is updated
/// only when its payload changes; a call event does not rewrite every contact.
public enum PhoneSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [AccountRow.self, ContactRow.self, HistoryRow.self, PreferencesRow.self] }

    @Model final class AccountRow {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class ContactRow {
        @Attribute(.unique) var id: UUID
        var name: String
        var payload: Data
        init(id: UUID, name: String, payload: Data) { self.id = id; self.name = name; self.payload = payload }
    }
    @Model final class HistoryRow {
        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var payload: Data
        init(id: UUID, startedAt: Date, payload: Data) { self.id = id; self.startedAt = startedAt; self.payload = payload }
    }
    @Model final class PreferencesRow {
        @Attribute(.unique) var key: String
        var payload: Data
        init(payload: Data) { self.key = "preferences"; self.payload = payload }
    }
}

public enum PhoneMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [PhoneSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

@MainActor public final class SwiftDataRepository: PhoneRepository {
    private let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL? = nil, inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: PhoneSchemaV1.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration("TelefonX", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        container = try ModelContainer(for: schema, migrationPlan: PhoneMigrationPlan.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public func load() throws -> AppSnapshot {
        var state: AppSnapshot
        if let preferences = try context.fetch(FetchDescriptor<PhoneSchemaV1.PreferencesRow>()).first {
            state = try decoder.decode(AppSnapshot.self, from: preferences.payload)
        } else { state = AppSnapshot() }
        state.accounts = AccountOrdering.ordered(
            try context.fetch(FetchDescriptor<PhoneSchemaV1.AccountRow>())
                .map { try decoder.decode(PhoneAccount.self, from: $0.payload) }
        )
        state.contacts = try context.fetch(FetchDescriptor<PhoneSchemaV1.ContactRow>()).map { try decoder.decode(PhoneContact.self, from: $0.payload) }.sorted { $0.name < $1.name }
        state.history = try context.fetch(FetchDescriptor<PhoneSchemaV1.HistoryRow>()).map { try decoder.decode(CallRecord.self, from: $0.payload) }.sorted { $0.startedAt > $1.startedAt }
        try state.validate()
        return state
    }

    public func save(_ snapshot: AppSnapshot) throws {
        try snapshot.validate()
        do {
            var accounts = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<PhoneSchemaV1.AccountRow>()).map { ($0.id, $0) })
            for value in snapshot.accounts {
                let data = try encoder.encode(value)
                if let row = accounts.removeValue(forKey: value.id) { if row.payload != data { row.payload = data } }
                else { context.insert(PhoneSchemaV1.AccountRow(id: value.id, payload: data)) }
            }
            accounts.values.forEach(context.delete)
            var contacts = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<PhoneSchemaV1.ContactRow>()).map { ($0.id, $0) })
            for value in snapshot.contacts {
                let data = try encoder.encode(value)
                if let row = contacts.removeValue(forKey: value.id) {
                    if row.payload != data { row.payload = data; row.name = value.name }
                } else { context.insert(PhoneSchemaV1.ContactRow(id: value.id, name: value.name, payload: data)) }
            }
            contacts.values.forEach(context.delete)
            var history = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<PhoneSchemaV1.HistoryRow>()).map { ($0.id, $0) })
            for value in snapshot.history {
                let data = try encoder.encode(value)
                if let row = history.removeValue(forKey: value.id) { if row.payload != data { row.payload = data } }
                else { context.insert(PhoneSchemaV1.HistoryRow(id: value.id, startedAt: value.startedAt, payload: data)) }
            }
            history.values.forEach(context.delete)
            var metadata = snapshot
            metadata.accounts = []; metadata.contacts = []; metadata.history = []
            let data = try encoder.encode(metadata)
            if let row = try context.fetch(FetchDescriptor<PhoneSchemaV1.PreferencesRow>()).first {
                if row.payload != data { row.payload = data }
            } else { context.insert(PhoneSchemaV1.PreferencesRow(payload: data)) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
