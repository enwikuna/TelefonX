import Foundation

enum DoNotDisturbDuration: CaseIterable, Identifiable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case untilDisabled

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtyMinutes: L10n.text("For 30 Minutes")
        case .oneHour: L10n.text("For 1 Hour")
        case .twoHours: L10n.text("For 2 Hours")
        case .untilDisabled: L10n.text("Until Turned Off")
        }
    }

    func endDate(from start: Date) -> Date? {
        let seconds: TimeInterval? = switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .untilDisabled: nil
        }
        return seconds.map { start.addingTimeInterval($0) }
    }
}
