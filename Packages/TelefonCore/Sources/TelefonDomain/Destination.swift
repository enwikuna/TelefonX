import Foundation

public struct CallDestination: Equatable, Hashable, Sendable {
    public let value: String
    public let isSIP: Bool

    public init(_ text: String) throws {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count <= 256, !input.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ValidationError.invalidDestination
        }
        if input.lowercased().hasPrefix("telefonx:") {
            guard let url = URLComponents(string: input), url.host == "call", url.query == nil, url.fragment == nil,
                  url.user == nil, url.password == nil else { throw ValidationError.invalidDestination }
            input = String(url.path.dropFirst())
        } else if input.lowercased().hasPrefix("tel:") {
            input = String(input.dropFirst(4)).removingPercentEncoding ?? ""
        }
        let isSecure = input.lowercased().hasPrefix("sips:")
        if input.lowercased().hasPrefix("sip:") || isSecure || input.contains("@") {
            if input.lowercased().hasPrefix("sip:") { input = String(input.dropFirst(4)) }
            else if isSecure { input = String(input.dropFirst(5)) }
            let parts = input.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, PhoneAccount.validHost(String(parts[1])),
                  parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.+*%".contains($0)) }) else {
                throw ValidationError.invalidDestination
            }
            guard let user = String(parts[0]).removingPercentEncoding,
                  user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.+*#".contains($0)) }) else {
                throw ValidationError.invalidDestination
            }
            self.value = (isSecure ? "sips:" : "sip:") + user.replacingOccurrences(of: "#", with: "%23") + "@" + parts[1].lowercased()
            self.isSIP = true
            return
        }
        if input.hasPrefix("+") || input.hasPrefix("00") { input = input.replacingOccurrences(of: "(0)", with: "") }
        let allowed = CharacterSet(charactersIn: "0123456789+*# ()-./\u{00a0}")
        guard !input.isEmpty, input.unicodeScalars.allSatisfy(allowed.contains) else { throw ValidationError.invalidDestination }
        let compact = input.filter { "0123456789+*#".contains($0) }
        guard (1...40).contains(compact.count), compact.contains(where: \.isNumber),
              !compact.dropFirst().contains("+"), compact != "+" else { throw ValidationError.invalidDestination }
        self.value = compact
        self.isSIP = false
    }

    public func uri(for account: PhoneAccount) throws -> String {
        if isSIP {
            guard !value.hasPrefix("sips:") || account.transport == .tls else { throw ValidationError.insecureMediaPolicy }
            return value
        }
        let user = value.replacingOccurrences(of: "#", with: "%23")
        return "sip:\(user)@\(account.domain);transport=\(account.transport.rawValue)"
    }

    /// Matching is deliberately conservative: extensions and service codes are never E.164-expanded.
    public func matchingKey(countryCode: String = "49") -> String {
        guard !isSIP, !value.contains("*"), !value.contains("#") else { return value }
        if value.hasPrefix("00") { return "+" + value.dropFirst(2) }
        if value.hasPrefix("0"), value.count >= 7 { return "+" + countryCode + value.dropFirst() }
        return value
    }

    public static func remoteAddress(from uri: String) -> String {
        let candidate = uri.range(of: #"sips?:[^<>\s;]+"#, options: [.regularExpression, .caseInsensitive])
        guard let candidate else { return uri }
        let token = String(uri[candidate])
        let user = String(token.dropFirst(token.lowercased().hasPrefix("sips:") ? 5 : 4).split(separator: "@").first ?? "")
            .removingPercentEncoding ?? ""
        if ["anonymous", "unavailable", "restricted", "unknown"].contains(user.lowercased()) { return user.lowercased() }
        if let number = try? CallDestination(user), !number.isSIP { return number.value }
        return (try? CallDestination(token).value) ?? uri
    }
}
