import Foundation
import TelefonData

enum KeychainCheck {
    /// A disposable value in a separate service; never reads SIP credentials.
    static func run() throws {
        let store = KeychainCredentials(service: "de.enwikuna.TelefonX.self-check")
        let id = UUID(), value = UUID().uuidString
        try store.setPassword(value, for: id)
        defer { try? store.deletePassword(for: id) }
        guard try store.password(for: id) == value else { throw AppError.storageUnavailable }
        try store.deletePassword(for: id)
        guard try store.password(for: id) == nil else { throw AppError.storageUnavailable }
    }
}
