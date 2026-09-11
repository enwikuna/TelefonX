import Foundation
@preconcurrency import MapKit
import TelefonDomain

struct PublicCallerIdentity: Equatable, Sendable {
    let name: String
    let matchedNumber: String
    let exact: Bool
}

protocol PublicCallerLookingUp: Sendable {
    func identity(for number: String) async -> PublicCallerIdentity?
}

enum PublicCallerNumbers {
    static func normalized(_ value: String) -> String? {
        guard let destination = try? CallDestination(value), !destination.isSIP else { return nil }
        let key = destination.matchingKey()
        guard key.hasPrefix("+"), key.dropFirst().allSatisfy(\.isNumber), (8...16).contains(key.count) else {
            return nil
        }
        return key
    }

    /// Public directories often list only a company's switchboard while SIP
    /// presents the complete extension. Generate a small, conservative set of
    /// German landline switchboard candidates by replacing a possible extension
    /// with the conventional terminal zero.
    static func lookupCandidates(for value: String) -> [String] {
        guard let number = normalized(value) else { return [] }
        var candidates = [number]
        guard number.hasPrefix("+49"), isLikelyGermanLandline(number) else { return candidates }

        for extensionLength in 1...5 where number.count - extensionLength >= 9 {
            let candidate = String(number.dropLast(extensionLength)) + "0"
            if !candidates.contains(candidate) { candidates.append(candidate) }
        }
        return candidates
    }

    static func isPlausibleSwitchboard(original: String, matched: String) -> Bool {
        guard original != matched, matched.hasSuffix("0") else { return false }
        let prefix = matched.dropLast()
        let extensionDigits = original.dropFirst(prefix.count)
        return original.hasPrefix(prefix) && (1...5).contains(extensionDigits.count)
            && extensionDigits.allSatisfy(\.isNumber)
    }

    private static func isLikelyGermanLandline(_ number: String) -> Bool {
        let national = number.dropFirst(3)
        guard let first = national.first, first != "0" else { return false }
        return !national.hasPrefix("15") && !national.hasPrefix("16") && !national.hasPrefix("17")
    }
}

actor MapKitPublicCallerLookup: PublicCallerLookingUp {
    private var hits: [String: PublicCallerIdentity] = [:]
    private var misses = Set<String>()

    func identity(for number: String) async -> PublicCallerIdentity? {
        guard let original = PublicCallerNumbers.normalized(number) else { return nil }
        if let cached = hits[original] { return cached }
        guard !misses.contains(original) else { return nil }

        for candidate in PublicCallerNumbers.lookupCandidates(for: original) {
            guard !Task.isCancelled else { return nil }
            guard let match = await search(candidate) else { continue }
            let exact = candidate == original
            guard exact || PublicCallerNumbers.isPlausibleSwitchboard(original: original, matched: candidate) else {
                continue
            }
            let identity = PublicCallerIdentity(name: match.name, matchedNumber: candidate, exact: exact)
            hits[original] = identity
            return identity
        }
        guard !Task.isCancelled else { return nil }
        misses.insert(original)
        return nil
    }

    private func search(_ number: String) async -> (name: String, phone: String)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = number
        request.resultTypes = .pointOfInterest
        do {
            let response = try await MKLocalSearch(request: request).start()
            for item in response.mapItems {
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                      let phone = item.phoneNumber,
                      PublicCallerNumbers.normalized(phone) == number else { continue }
                return (name, phone)
            }
        } catch {
            return nil
        }
        return nil
    }
}
