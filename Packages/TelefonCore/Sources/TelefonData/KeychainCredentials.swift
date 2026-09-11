import Foundation
import Security
import TelefonDomain

public struct KeychainCredentials: CredentialStore {
    private let service: String
    public init(service: String = "de.enwikuna.TelefonX.sip") { self.service = service }
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString, kSecAttrSynchronizable as String: false]
    }
    public func password(for id: UUID) throws -> String? {
        var attributes = query(id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw EngineError(Int(status), operation: "Zugriff auf Schlüsselbund")
        }
        return value
    }
    public func setPassword(_ password: String, for id: UUID) throws {
        let changes = [kSecValueData as String: Data(password.utf8)]
        var status = SecItemUpdate(query(id) as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(id).merging(changes) { _, new in new }
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw EngineError(Int(status), operation: "Passwort speichern") }
    }
    public func deletePassword(for id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw EngineError(Int(status), operation: "Passwort entfernen") }
    }
}
