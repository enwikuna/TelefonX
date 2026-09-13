import Foundation
import TelefonDomain

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All", missed = "Missed", incoming = "Incoming", outgoing = "Outgoing", blocked = "Blocked"
    var id: Self { self }
    var title: String { L10n.text(rawValue) }
    var emptyTitle: String {
        switch self {
        case .all: L10n.text("No Calls Yet")
        case .missed: L10n.text("No Missed Calls")
        case .incoming: L10n.text("No Incoming Calls")
        case .outgoing: L10n.text("No Outgoing Calls")
        case .blocked: L10n.text("No Blocked Calls")
        }
    }
    var symbol: String {
        switch self {
        case .all: "phone.fill"
        case .missed: "phone.arrow.down.left.fill"
        case .incoming: "arrow.down.left"
        case .outgoing: "arrow.up.right"
        case .blocked: "hand.raised.fill"
        }
    }
    func includes(_ record: CallRecord) -> Bool {
        switch self {
        case .all: true
        case .missed: record.outcome == .missed
        case .incoming: record.incoming
        case .outgoing: !record.incoming
        case .blocked: record.outcome == .blocked
        }
    }
}

enum HistoryPresentation {
    static func blockedSymbol(for remote: String, rules: [BlockRule]) -> String? {
        Routing.isBlocked(remote, rules: rules, anonymous: false) ? "hand.raised.fill" : nil
    }

    static func contactDraft(number: String, displayName: String) -> PhoneContact {
        let suggestedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return PhoneContact(name: suggestedName == number || suggestedName.isEmpty ? "" : suggestedName,
                            numbers: [number])
    }

    static func records(_ history: [CallRecord], filter: HistoryFilter, hideBlockedInAll: Bool = false, search: String,
                        displayName: (String) -> String) -> [CallRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return history.filter { record in
            let hiddenBlockedCall = filter == .all && hideBlockedInAll && record.outcome == .blocked
            return filter.includes(record) && !hiddenBlockedCall && (query.isEmpty
                || record.remote.localizedCaseInsensitiveContains(query)
                || displayName(record.remote).localizedCaseInsensitiveContains(query))
        }.sorted {
            if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startedAt > $1.startedAt
        }
    }

    /// The separator belongs to the gap; neither edge of a selected row is ruled.
    static func showsSeparator(after row: Int, count: Int, selectedRow: Int?) -> Bool {
        showsSeparator(after: row, count: count,
                       selectedRows: selectedRow.map { IndexSet(integer: $0) } ?? IndexSet())
    }

    static func showsSeparator(after row: Int, count: Int, selectedRows: IndexSet) -> Bool {
        row >= 0 && row < count - 1 && !selectedRows.contains(row) && !selectedRows.contains(row + 1)
    }

    static func timestamp(_ date: Date, relativeTo now: Date, calendar: Calendar = .current,
                          locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch days {
        case 0: return date.formatted(style.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        case 1: return L10n.text("Yesterday")
        case 2..<7: return date.formatted(style.weekday(.wide))
        default: return date.formatted(style.day(.twoDigits).month(.twoDigits).year(.twoDigits))
        }
    }

    static func detail(_ record: CallRecord) -> String {
        guard record.outcome == .answered else { return outcome(record) }
        guard record.duration.isFinite, record.duration >= 0 else { return "" }
        return Duration.seconds(record.duration).formatted(.time(pattern: record.duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    static func secondaryText(_ record: CallRecord, displayName: String) -> String {
        [record.accountName, displayName == record.remote ? "" : record.remote, detail(record)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    static func outcome(_ record: CallRecord) -> String {
        switch record.outcome {
        case .answered: L10n.text(record.incoming ? "Incoming" : "Outgoing")
        case .missed: L10n.text("Missed")
        case .declined: L10n.text("Declined")
        case .failed: L10n.text("Unanswered")
        case .blocked: L10n.text("Blocked")
        }
    }
}
