import Foundation

public struct AudioDevice: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var inputChannels: Int
    public var outputChannels: Int
    public var engineIndex: Int32
    public init(id: String, name: String, inputChannels: Int, outputChannels: Int, engineIndex: Int32) {
        self.id = id; self.name = name; self.inputChannels = inputChannels
        self.outputChannels = outputChannels; self.engineIndex = engineIndex
    }
}

public enum TelephonyEvent: Sendable {
    case registration(UUID, RegistrationState)
    case call(CallHandle, accountID: UUID, remote: String, incoming: Bool, phase: CallPhase, status: Int)
    case media(CallHandle, held: Bool, remoteHeld: Bool, error: Int)
    case transfer(CallHandle, status: Int, final: Bool)
    case failure(Int)
}

public struct EngineError: Error, LocalizedError, Sendable {
    public static let invalidOperationCode = 70_013
    public let code: Int
    public let operation: String
    public init(_ code: Int, operation: String) { self.code = code; self.operation = operation }
    public var errorDescription: String? {
        if code == 171173 { return "Das TLS-Zertifikat der Telefonanlage ist nicht vertrauenswürdig oder passt nicht zum Servernamen. Die Verbindung wurde abgelehnt. Bitte Servername, Systemzeit und Zertifikat beim Anbieter prüfen." }
        return "\(operation) fehlgeschlagen (Code \(code)). Details und Verbindung bitte unter Diagnose prüfen."
    }
}

public protocol TelephonyService: Sendable {
    var events: AsyncStream<TelephonyEvent> { get }
    func start() async throws
    /// Completes native teardown, then finishes `events`. Consumers must drain
    /// the stream to persist buffered terminal call events before exiting.
    func stop() async
    func register(_ account: PhoneAccount, password: String) async throws
    func unregister(_ id: UUID) async throws
    /// Requests an immediate SIP registration refresh and waits briefly for the
    /// registrar's response. This catches stale `registered` state after a
    /// route or VPN disappears before an outgoing INVITE is created.
    func verifyRegistration(_ id: UUID) async throws -> Bool
    func call(_ destination: CallDestination, account: PhoneAccount) async throws -> CallHandle
    func answer(_ call: CallHandle) async throws
    func hangup(_ call: CallHandle, decline: Bool) async throws
    func mute(_ call: CallHandle, muted: Bool) async throws
    func hold(_ call: CallHandle, held: Bool) async throws
    func setHoldMusic(_ file: URL?) async throws
    func sendDTMF(_ digit: String, call: CallHandle) async throws
    func conference(_ first: CallHandle, with second: CallHandle, enabled: Bool) async throws
    func transfer(_ source: CallHandle, to consultation: CallHandle) async throws
    func quality(_ call: CallHandle) async throws -> CallQuality
    func audioDevices() async throws -> [AudioDevice]
    func setAudio(input: Int32, output: Int32) async throws
    func releaseAudio() async
    func networkChanged() async throws
}

@MainActor public protocol PhoneRepository {
    func load() throws -> AppSnapshot
    func save(_ snapshot: AppSnapshot) throws
}

public protocol CredentialStore: Sendable {
    func password(for id: UUID) throws -> String?
    func setPassword(_ password: String, for id: UUID) throws
    func deletePassword(for id: UUID) throws
}

public struct AppSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var accounts: [PhoneAccount] = []
    public var contacts: [PhoneContact] = []
    public var history: [CallRecord] = []
    public var reminders: [CallReminder] = []
    public var blocks: [BlockRule] = []
    public var dialRules: [DialRule] = []
    public var defaultAccountID: UUID?
    public var blockAnonymous = false
    public var holdMusic: AudioAsset?
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, accounts, contacts, history, reminders, blocks, dialRules
        case defaultAccountID, blockAnonymous, holdMusic
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        accounts = try values.decodeIfPresent([PhoneAccount].self, forKey: .accounts) ?? []
        contacts = try values.decodeIfPresent([PhoneContact].self, forKey: .contacts) ?? []
        history = try values.decodeIfPresent([CallRecord].self, forKey: .history) ?? []
        reminders = try values.decodeIfPresent([CallReminder].self, forKey: .reminders) ?? []
        blocks = try values.decodeIfPresent([BlockRule].self, forKey: .blocks) ?? []
        dialRules = try values.decodeIfPresent([DialRule].self, forKey: .dialRules) ?? []
        defaultAccountID = try values.decodeIfPresent(UUID.self, forKey: .defaultAccountID)
        blockAnonymous = try values.decodeIfPresent(Bool.self, forKey: .blockAnonymous) ?? false
        holdMusic = try values.decodeIfPresent(AudioAsset.self, forKey: .holdMusic)
    }
    public func validate() throws {
        try holdMusic?.validate()
        guard schemaVersion == 1 else { throw ValidationError.unsupportedVersion }
        guard accounts.count <= 32, contacts.count <= 100_000, history.count <= 200_000, reminders.count <= 10_000,
              Set(accounts.map(\.id)).count == accounts.count, Set(contacts.map(\.id)).count == contacts.count,
              Set(history.map(\.id)).count == history.count, Set(reminders.map(\.id)).count == reminders.count,
              Set(blocks.map(\.id)).count == blocks.count,
              Set(dialRules.map(\.id)).count == dialRules.count else { throw ValidationError.invalidBackup }
        let accountRanks = accounts.compactMap(\.sortIndex)
        guard accountRanks.allSatisfy({ (0..<32).contains($0) }),
              Set(accountRanks).count == accountRanks.count else { throw ValidationError.invalidBackup }
        try accounts.forEach { try $0.validate() }
        for contact in contacts {
            guard !contact.name.isEmpty, contact.name.count <= 200, contact.notes.count <= 100_000,
                  contact.numbers.count <= 20, contact.hasConsistentPhoneNumberLabels,
                  (contact.photoData?.count ?? 0) <= PhoneContact.maximumPhotoBytes else { throw ValidationError.invalidBackup }
            try contact.numbers.forEach { _ = try CallDestination($0) }
            if let number = contact.favoriteNumber { _ = try CallDestination(number) }
            if let order = contact.favoriteOrder, !(0..<100_000).contains(order) { throw ValidationError.invalidBackup }
        }
        guard contacts.reduce(0, { $0 + ($1.photoData?.count ?? 0) }) <= 32_000_000 else { throw ValidationError.invalidBackup }
        try blocks.forEach { _ = try CallDestination($0.number) }
        for reminder in reminders {
            guard !reminder.name.isEmpty, reminder.name.count <= 200, reminder.note.count <= 10_000,
                  reminder.number.count <= 1024 else { throw ValidationError.invalidBackup }
            _ = try CallDestination(reminder.number)
        }
        let ids = Set(accounts.map(\.id))
        guard defaultAccountID.map(ids.contains) ?? true,
              dialRules.allSatisfy({ ids.contains($0.accountID) && !$0.prefix.isEmpty }),
              history.allSatisfy({ $0.duration.isFinite && $0.duration >= 0 && $0.remote.count <= 1024 }) else {
            throw ValidationError.invalidBackup
        }
    }
}
