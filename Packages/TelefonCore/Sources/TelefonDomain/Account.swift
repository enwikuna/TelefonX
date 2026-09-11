import Foundation

public enum SIPTransport: String, Codable, CaseIterable, Sendable {
    case udp, tcp, tls
}

public struct PhoneAccount: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var username: String
    public var authenticationName: String
    public var domain: String
    public var registrar: String
    public var proxy: String
    public var transport: SIPTransport
    public var enabled: Bool
    public var requireSRTP: Bool
    public var useICE: Bool
    public var stunServer: String
    public var g711Only: Bool
    public var registrationInterval: Int
    // Optional additions keep existing stored accounts and backups decodable.
    public var ringtone: LineRingtone?
    public var suppressCallerID: Bool
    public var sortIndex: Int?

    public init(id: UUID = UUID(), name: String = "", username: String = "", authenticationName: String = "",
                domain: String = "", registrar: String = "", proxy: String = "", transport: SIPTransport = .udp,
                enabled: Bool = true, requireSRTP: Bool = false, useICE: Bool = false,
                stunServer: String = "", g711Only: Bool = false, registrationInterval: Int = 300,
                suppressCallerID: Bool = false, sortIndex: Int? = nil) {
        self.id = id; self.name = name; self.username = username; self.authenticationName = authenticationName
        self.domain = domain; self.registrar = registrar; self.proxy = proxy; self.transport = transport
        self.enabled = enabled; self.requireSRTP = requireSRTP; self.useICE = useICE
        self.stunServer = stunServer; self.g711Only = g711Only; self.registrationInterval = registrationInterval
        self.suppressCallerID = suppressCallerID; self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, username, authenticationName, domain, registrar, proxy, transport, enabled
        case requireSRTP, useICE, stunServer, g711Only, registrationInterval, ringtone, suppressCallerID, sortIndex
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        username = try values.decode(String.self, forKey: .username)
        authenticationName = try values.decode(String.self, forKey: .authenticationName)
        domain = try values.decode(String.self, forKey: .domain)
        registrar = try values.decode(String.self, forKey: .registrar)
        proxy = try values.decode(String.self, forKey: .proxy)
        transport = try values.decode(SIPTransport.self, forKey: .transport)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        requireSRTP = try values.decode(Bool.self, forKey: .requireSRTP)
        useICE = try values.decode(Bool.self, forKey: .useICE)
        stunServer = try values.decode(String.self, forKey: .stunServer)
        g711Only = try values.decode(Bool.self, forKey: .g711Only)
        registrationInterval = try values.decode(Int.self, forKey: .registrationInterval)
        ringtone = try values.decodeIfPresent(LineRingtone.self, forKey: .ringtone)
        suppressCallerID = try values.decodeIfPresent(Bool.self, forKey: .suppressCallerID) ?? false
        sortIndex = try values.decodeIfPresent(Int.self, forKey: .sortIndex)
    }

    public func validate() throws {
        if case .file(let asset) = ringtone { try asset.validate() }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 80 else { throw ValidationError.invalidAccount }
        guard Self.validHost(domain), registrar.isEmpty || Self.validHost(registrar), proxy.isEmpty || Self.validHost(proxy),
              stunServer.isEmpty || Self.validHost(stunServer) else { throw ValidationError.invalidHost }
        guard !username.isEmpty, username.count <= 128,
              username.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.+*".contains($0)) }),
              authenticationName.count <= 128,
              !authenticationName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (60...3600).contains(registrationInterval) else { throw ValidationError.invalidAccount }
        // SDES keys must never be sent over plaintext SIP.
        guard !requireSRTP || transport == .tls else { throw ValidationError.insecureMediaPolicy }
    }

    public static func validHost(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253 else { return false }
        let pattern = #"^(?:[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:]+\])(?::[0-9]{1,5})?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return false }
        if let portPart = value.split(separator: "]").last, portPart.hasPrefix(":"), let port = Int(portPart.dropFirst()) {
            return (1...65535).contains(port)
        }
        if !value.hasPrefix("["), let index = value.lastIndex(of: ":") {
            guard let port = Int(value[value.index(after: index)...]), (1...65535).contains(port) else { return false }
        }
        return !value.contains("..")
    }
}

public enum AccountOrdering {
    /// Legacy accounts have no explicit rank and retain their previous,
    /// deterministic alphabetical order until the user reorders them.
    public static func ordered(_ accounts: [PhoneAccount]) -> [PhoneAccount] {
        accounts.sorted { lhs, rhs in
            switch (lhs.sortIndex, rhs.sortIndex) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                let result = lhs.name.localizedStandardCompare(rhs.name)
                if result != .orderedSame { return result == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    public static func numbered(_ accounts: [PhoneAccount]) -> [PhoneAccount] {
        accounts.enumerated().map { index, account in
            var account = account
            account.sortIndex = index
            return account
        }
    }
}

public enum RegistrationState: Equatable, Sendable {
    case disabled, registering, registered, failed(Int), offline
}

public enum ValidationError: Error, Equatable, LocalizedError {
    case invalidAccount, invalidHost, invalidDestination, insecureMediaPolicy, invalidBackup, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .invalidAccount: "Bitte Leitungsname, Benutzername und Registrierungsintervall prüfen."
        case .invalidHost: "Server als Hostname oder IP-Adresse angeben, optional mit Port – ohne sip:// oder Pfad."
        case .invalidDestination: "Bitte eine gültige Telefonnummer, Nebenstelle oder SIP-Adresse eingeben."
        case .insecureMediaPolicy: "Verschlüsselte Medien erfordern in TelefonX auch TLS für die Signalisierung."
        case .invalidBackup: "Die Datei enthält ungültige oder doppelte Datensätze. Es wurden keine Daten übernommen."
        case .unsupportedVersion: "Diese Sicherungsversion wird nicht unterstützt."
        }
    }
}
