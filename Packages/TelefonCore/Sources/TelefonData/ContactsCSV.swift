import Foundation
import TelefonDomain

public enum ContactsCSV {
    public static func encode(_ contacts: [PhoneContact]) -> String {
        let rows = [["Name", "Firma", "Telefon", "E-Mail", "Notizen", "Gruppe", "Telefontypen"]] + contacts.map {
            [$0.name, $0.company, $0.numbers.joined(separator: " | "), $0.email, $0.notes, $0.group,
             $0.phoneNumbers.map(\.label.rawValue).joined(separator: " | ")]
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
    }
    static func escape(_ field: String) -> String {
        // Quote cells, and prevent spreadsheet formula execution for user-controlled text.
        let safe = needsPrefix(field) ? "'" + field : field
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private static func needsPrefix(_ field: String) -> Bool {
        field.hasPrefix("'") || field.first.map({ "\t\r\n".contains($0) }) == true ||
            field.trimmingCharacters(in: .whitespacesAndNewlines).first.map({ "=+@-".contains($0) }) == true
    }
    public static func decode(_ text: String) throws -> [PhoneContact] {
        guard text.utf8.count <= 20_000_000 else { throw ValidationError.invalidBackup }
        let normalized = text.replacingOccurrences(of: "\u{feff}", with: "")
        let firstLine = normalized.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = firstLine.contains(";") && !firstLine.contains(",") ? ";" : ","
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == delimiter && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r\n" || c == "\r") && !quoted {
                row.append(field); rows.append(row); row = []; field = ""
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw ValidationError.invalidBackup }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }),
              let nameIndex = header.firstIndex(of: "name"), let phoneIndex = header.firstIndex(where: { ["telefon", "phone", "numbers"].contains($0) }) else {
            throw ValidationError.invalidBackup
        }
        return try rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { fields in
            func cell(_ index: Int?) -> String {
                guard let index, fields.indices.contains(index) else { return "" }
                let value = fields[index]
                if value.hasPrefix("'"), needsPrefix(String(value.dropFirst())) { return String(value.dropFirst()) }
                return value
            }
            let numbers = cell(phoneIndex).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            try numbers.forEach { _ = try CallDestination($0) }
            guard !cell(nameIndex).isEmpty, !numbers.isEmpty else { throw ValidationError.invalidBackup }
            let labelIndex = header.firstIndex(where: { ["telefontypen", "phone types", "phone labels"].contains($0) })
            let encodedLabels = cell(labelIndex).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let labels: [ContactPhoneLabel]? = labelIndex.map { _ in
                numbers.indices.map { index in
                    encodedLabels.indices.contains(index) ? ContactPhoneLabel(rawValue: encodedLabels[index]) ?? .other : .other
                }
            }
            return PhoneContact(name: cell(nameIndex), company: cell(header.firstIndex(where: { ["firma", "company"].contains($0) })),
                                numbers: numbers, email: cell(header.firstIndex(where: { ["e-mail", "email"].contains($0) })),
                                notes: cell(header.firstIndex(where: { ["notizen", "notes"].contains($0) })),
                                group: cell(header.firstIndex(where: { ["gruppe", "group"].contains($0) })), phoneNumberLabels: labels)
        }
    }
}
