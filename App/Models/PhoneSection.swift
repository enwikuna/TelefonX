import Foundation

enum PhoneSection: String, CaseIterable, Identifiable {
    case history = "Recents", reminders = "Call Reminders", favorites = "Favorites", contacts = "Contacts"
    var id: String { rawValue }
    var title: String { L10n.text(rawValue) }
    var icon: String {
        switch self {
        case .history: "clock"
        case .reminders: "calendar.badge.clock"
        case .favorites: "star"
        case .contacts: "person.crop.rectangle"
        }
    }

    func moved(by offset: Int) -> Self {
        let items = Self.allCases
        let index = items.firstIndex(of: self) ?? 0
        return items[min(max(index + offset, 0), items.count - 1)]
    }
}
