import Foundation
import TelefonDomain

/// A portable snapshot of recents that remains available without a configured line.
public enum HistoryCSV {
    public static func encode(_ records: [CallRecord], displayName: (String) -> String) -> String {
        let date = ISO8601DateFormatter()
        let rows = [["Name", "Telefon", "Richtung", "Zeitpunkt", "Dauer in Sekunden", "Status", "Leitung", "Codec"]] + records.map {
            [displayName($0.remote), $0.remote, $0.incoming ? "Eingehend" : "Ausgehend",
             date.string(from: $0.startedAt), String(Int($0.duration.rounded())), outcome($0.outcome),
             $0.accountName, $0.codec]
        }
        return rows.map { $0.map(ContactsCSV.escape).joined(separator: ",") }.joined(separator: "\r\n")
    }

    private static func outcome(_ outcome: CallOutcome) -> String {
        switch outcome {
        case .answered: "Angenommen"
        case .missed: "Verpasst"
        case .declined: "Abgelehnt"
        case .failed: "Fehlgeschlagen"
        case .blocked: "Blockiert"
        }
    }
}
