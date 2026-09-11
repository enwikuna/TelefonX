import Foundation

public struct AudioAsset: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
    public func validate() throws {
        guard !name.isEmpty, name.count <= 200 else { throw ValidationError.invalidBackup }
    }
}

public enum BuiltinRingtone: String, Codable, CaseIterable, Sendable {
    // Keep Glass first because it is TelefonX's default; the remaining public
    // macOS sounds follow alphabetically in the picker.
    case glass = "Glass"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    public var title: String {
        switch self {
        case .glass: "Glas (Standard)"
        case .basso: "Basso"
        case .blow: "Blasgeräusch"
        case .bottle: "Flasche"
        case .frog: "Frosch"
        case .funk: "Impuls"
        case .hero: "Signal"
        case .morse: "Morse"
        case .ping: "Ping"
        case .pop: "Pop"
        case .purr: "Schnurren"
        case .sosumi: "Sosumi"
        case .submarine: "Sonar"
        case .tink: "Tink"
        }
    }
}

public enum LineRingtone: Codable, Hashable, Sendable {
    case system(BuiltinRingtone)
    case file(AudioAsset)
    public var title: String {
        switch self { case .system(let sound): sound.title; case .file(let asset): asset.name }
    }
}

public enum RingtoneRouting {
    /// Only one ringtone at a time; the oldest unanswered incoming call wins.
    public static func incoming(in calls: [CallSession]) -> CallSession? {
        calls.filter { $0.incoming && !$0.blocked && $0.answeredAt == nil && [.incoming, .ringing].contains($0.phase) }
            .sorted { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt }.first
    }
    public static func sound(for call: CallSession, accounts: [PhoneAccount]) -> LineRingtone {
        accounts.first { $0.id == call.accountID }?.ringtone ?? .system(.glass)
    }
}
