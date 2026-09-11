import Foundation
import TelefonDomain

/// Data portability remains available even when reminder functionality is locked.
public enum RemindersCSV {
    public static func encode(_ reminders: [CallReminder]) -> String {
        let date = ISO8601DateFormatter()
        let rows = [["Name", "Telefon", "Termin", "Notizen", "Status", "Erledigt am"]] + reminders.map {
            [$0.name, $0.number, date.string(from: $0.dueAt), $0.note,
             $0.completedAt == nil ? "Offen" : "Erledigt", $0.completedAt.map(date.string) ?? ""]
        }
        return rows.map { $0.map(ContactsCSV.escape).joined(separator: ",") }.joined(separator: "\r\n")
    }
}
