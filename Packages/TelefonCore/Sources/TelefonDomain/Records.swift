import Foundation

public enum ContactPhoneLabel: String, Codable, CaseIterable, Sendable {
    case mobile
    case home
    case work
    case other
}

public struct ContactPhoneNumber: Codable, Equatable, Sendable {
    public var value: String
    public var label: ContactPhoneLabel

    public init(value: String, label: ContactPhoneLabel) {
        self.value = value
        self.label = label
    }
}

public struct PhoneContact: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var company: String
    public var numbers: [String]
    public var email: String
    public var notes: String
    public var group: String
    public var favorite: Bool
    public var favoriteNumber: String?
    public var favoriteOrder: Int?
    public var preferredAccountID: UUID?
    /// Bounded JPEG thumbnail without source metadata; nil for older contacts.
    public var photoData: Data?
    /// Kept optional so existing contact payloads decode without a migration.
    private var phoneNumberLabels: [ContactPhoneLabel]?
    public static let maximumPhotoBytes = 128_000

    public var phoneNumbers: [ContactPhoneNumber] {
        get {
            numbers.enumerated().map { index, value in
                ContactPhoneNumber(value: value, label: phoneNumberLabels?[safe: index] ?? .other)
            }
        }
        set {
            numbers = newValue.map(\.value)
            phoneNumberLabels = newValue.map(\.label)
        }
    }

    public var hasConsistentPhoneNumberLabels: Bool {
        phoneNumberLabels.map { $0.count == numbers.count } ?? true
    }

    public init(id: UUID = UUID(), name: String = "", company: String = "", numbers: [String] = [], email: String = "",
                notes: String = "", group: String = "", favorite: Bool = false, preferredAccountID: UUID? = nil, photoData: Data? = nil,
                favoriteNumber: String? = nil, favoriteOrder: Int? = nil, phoneNumberLabels: [ContactPhoneLabel]? = nil) {
        self.id = id; self.name = name; self.company = company; self.numbers = numbers; self.email = email
        self.notes = notes; self.group = group; self.favorite = favorite; self.preferredAccountID = preferredAccountID
        self.photoData = photoData
        self.favoriteNumber = favoriteNumber; self.favoriteOrder = favoriteOrder
        self.phoneNumberLabels = phoneNumberLabels
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

public enum CallOutcome: String, Codable, Sendable { case answered, missed, declined, failed, blocked }

public struct CallRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var accountID: UUID
    public var accountName: String
    public var remote: String
    public var incoming: Bool
    public var startedAt: Date
    public var duration: TimeInterval
    public var outcome: CallOutcome
    public var codec: String
    public init(session: CallSession, accountName: String) {
        id = session.id; accountID = session.accountID; self.accountName = accountName; remote = session.remote
        incoming = session.incoming; startedAt = session.startedAt
        duration = session.answeredAt.map { max(0, (session.endedAt ?? Date()).timeIntervalSince($0)) } ?? 0
        if session.blocked { outcome = .blocked }
        else if session.answeredAt != nil { outcome = .answered }
        else if session.locallyDeclined { outcome = .declined }
        else { outcome = session.incoming ? .missed : .failed }
        codec = session.quality?.codec ?? ""
    }
}

/// A deliberately small, call-specific follow-up. The copied name and number
/// keep the reminder useful even when its source call or contact is deleted.
public struct CallReminder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var number: String
    public var note: String
    public var dueAt: Date
    public var createdAt: Date
    public var completedAt: Date?
    public var accountID: UUID?
    public var contactID: UUID?
    public var sourceCallID: UUID?
    public var notificationTiming: CallReminderNotificationTiming?

    public init(id: UUID = UUID(), name: String, number: String, note: String = "", dueAt: Date,
                createdAt: Date = Date(), completedAt: Date? = nil, accountID: UUID? = nil,
                contactID: UUID? = nil, sourceCallID: UUID? = nil,
                notificationTiming: CallReminderNotificationTiming? = nil) {
        self.id = id
        self.name = name
        self.number = number
        self.note = note
        self.dueAt = dueAt
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.accountID = accountID
        self.contactID = contactID
        self.sourceCallID = sourceCallID
        self.notificationTiming = notificationTiming
    }
}

public enum CallReminderNotificationTiming: String, Codable, CaseIterable, Sendable {
    case none
    case atTime
    case fiveMinutesBefore
    case tenMinutesBefore

    public var leadTime: TimeInterval? {
        switch self {
        case .none: nil
        case .atTime: 0
        case .fiveMinutesBefore: 5 * 60
        case .tenMinutesBefore: 10 * 60
        }
    }
}

public struct BlockRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var number: String
    public var createdAt: Date
    public init(id: UUID = UUID(), number: String, createdAt: Date = Date()) {
        self.id = id; self.number = number; self.createdAt = createdAt
    }
}

public struct DialRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var prefix: String
    public var accountID: UUID
    public init(id: UUID = UUID(), prefix: String, accountID: UUID) {
        self.id = id; self.prefix = prefix; self.accountID = accountID
    }
}

public enum Routing {
    public static func account(for number: String, rules: [DialRule], available: Set<UUID>, fallback: UUID?) -> UUID? {
        rules.filter { available.contains($0.accountID) && !$0.prefix.isEmpty && number.hasPrefix($0.prefix) }
            .sorted { $0.prefix.count > $1.prefix.count }.first?.accountID
            ?? fallback.flatMap { available.contains($0) ? $0 : nil }
    }
    public static func isBlocked(_ remote: String, rules: [BlockRule], anonymous: Bool) -> Bool {
        if anonymous && ["anonymous", "unavailable", "restricted", "unknown"].contains(remote.lowercased()) { return true }
        guard let key = try? CallDestination(remote).matchingKey() else { return false }
        return rules.contains { (try? CallDestination($0.number).matchingKey()) == key }
    }
}
