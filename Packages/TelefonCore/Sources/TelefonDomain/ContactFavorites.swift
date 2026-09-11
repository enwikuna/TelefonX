import Foundation

public struct FavoriteChoice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var number: String?
    public init(id: UUID, number: String?) { self.id = id; self.number = number }
}

public enum ContactFavorites {
    public static func ordered(_ contacts: [PhoneContact]) -> [PhoneContact] {
        contacts.filter(\.favorite).sorted {
            let left = $0.favoriteOrder ?? Int.max, right = $1.favoriteOrder ?? Int.max
            if left != right { return left < right }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    public static func number(for contact: PhoneContact) -> String? {
        if let preferred = contact.favoriteNumber,
           let current = contact.numbers.first(where: { equivalent($0, preferred) }) { return current }
        return contact.numbers.first
    }

    public static func choices(_ contacts: [PhoneContact]) -> [FavoriteChoice] {
        ordered(contacts).map { FavoriteChoice(id: $0.id, number: number(for: $0)) }
    }

    public static func equivalent(_ first: String, _ second: String) -> Bool {
        guard let left = try? CallDestination(first).matchingKey(), let right = try? CallDestination(second).matchingKey() else { return false }
        return left == right
    }
}
