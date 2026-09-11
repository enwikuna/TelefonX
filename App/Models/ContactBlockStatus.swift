import TelefonDomain

struct ContactBlockStatus: Equatable {
    let blocked: Int
    let valid: Int

    var hasBlockedNumbers: Bool { blocked > 0 }
    var canBlockMore: Bool { valid > blocked }
    var label: String {
        L10n.text(blocked == valid ? "Blocked" : "Partially Blocked")
    }

    static func resolve(_ contact: PhoneContact, rules: [BlockRule]) -> Self {
        let validNumbers = contact.numbers.filter { (try? CallDestination($0)) != nil }
        let blocked = validNumbers.filter { Routing.isBlocked($0, rules: rules, anonymous: false) }.count
        return Self(blocked: blocked, valid: validNumbers.count)
    }
}
