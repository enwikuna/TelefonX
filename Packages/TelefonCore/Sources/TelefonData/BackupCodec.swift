import Foundation
import TelefonDomain

public enum BackupCodec {
    /// No credential data is represented in AppSnapshot, therefore none can leak into exports.
    public static func encode(_ snapshot: AppSnapshot) throws -> Data {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }
    public static func decode(_ data: Data) throws -> AppSnapshot {
        guard data.count <= 100_000_000 else { throw ValidationError.invalidBackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AppSnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }
}
