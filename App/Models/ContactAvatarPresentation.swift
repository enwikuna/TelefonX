import Foundation
import TelefonDomain

enum ContactAvatarPresentation {
    struct ColorComponents: Hashable {
        let red: Double
        let green: Double
        let blue: Double
    }

    static func monogram(name: String, company: String = "", locale: Locale = .current) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, (try? CallDestination(name)) == nil,
              !["unknown", "anonymous", "unavailable", "restricted", "unknown"].contains(name.lowercased()) else { return nil }
        let letters = name.filter { $0.isLetter }
        guard !letters.isEmpty else { return nil }
        if !company.isEmpty, name == company { return String(letters.prefix(1)).uppercased(with: locale) }
        let formatter = PersonNameComponentsFormatter()
        formatter.locale = locale
        formatter.style = .abbreviated
        if let components = formatter.personNameComponents(from: name) {
            let abbreviated = formatter.string(from: components).filter { $0.isLetter }
            if !abbreviated.isEmpty { return String(abbreviated.prefix(3)) }
        }
        return String(letters.prefix(1)).uppercased(with: locale)
    }

    /// Unlike Swift's randomized Hasher, this stays stable across app launches.
    /// A continuous hue avoids the frequent collisions caused by a small fixed palette.
    static func colorComponents(for id: UUID) -> ColorComponents {
        let hash = id.uuidString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        return hsl(hue: hue, saturation: 0.50, lightness: 0.31)
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> ColorComponents {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue * 6
        let intermediate = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let values: (Double, Double, Double) = switch Int(sector) % 6 {
        case 0: (chroma, intermediate, 0)
        case 1: (intermediate, chroma, 0)
        case 2: (0, chroma, intermediate)
        case 3: (0, intermediate, chroma)
        case 4: (intermediate, 0, chroma)
        default: (chroma, 0, intermediate)
        }
        let match = lightness - chroma / 2
        return ColorComponents(red: values.0 + match, green: values.1 + match, blue: values.2 + match)
    }
}
