import Foundation
import Testing
@testable import TelefonX

@Suite struct LocalizationTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func strings(_ language: String, file: String = "Localizable") throws -> [String: String] {
        let url = repository.appending(path: "App/Resources/\(language).lproj/\(file).strings")
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    @Test func englishIsTheDevelopmentAndFallbackLanguage() throws {
        let manifest = try String(contentsOf: repository.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains("defaultLocalization: \"en\""))

        let infoData = try Data(contentsOf: repository.appending(path: "script/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any])
        #expect(info["CFBundleDevelopmentRegion"] as? String == "en")
    }

    @Test func bothLanguagesContainLocalizedPrivacyText() throws {
        let english = try strings("en", file: "InfoPlist")
        let german = try strings("de", file: "InfoPlist")
        #expect(english["NSMicrophoneUsageDescription"]?.contains("calls") == true)
        #expect(german["NSMicrophoneUsageDescription"]?.contains("Telefonate") == true)
        #expect(english["NSContactsUsageDescription"]?.contains("contacts") == true)
        #expect(german["NSContactsUsageDescription"]?.contains("Kontakte") == true)
    }

    @Test func englishCatalogCoversRepresentativeStaticDynamicAndErrorText() throws {
        let english = try strings("en")
        #expect(english["Recents"] == "Recents")
        #expect(english["Call Reminders"] == "Call Reminders")
        #expect(english["Apple Contacts"] == "Apple Contacts")
        #expect(english["Insert This Line's Last Number"] == "Insert This Line's Last Number")
        #expect(english["Insert Last Number Dialed on %@: %@"] != nil)
        #expect(english["%lld Calls"] == "%lld Calls")
        #expect(english["On Hold"] == "On Hold")
        #expect(english["Enter a valid phone number, extension, or SIP address."] != nil)
        #expect(english["The phone system's TLS certificate is not trusted or does not match the server name. The connection was rejected. Check the server name, system time, and certificate with your provider."] != nil)
    }

    @Test func englishCatalogHasNoDuplicateKeys() throws {
        let url = repository.appending(path: "App/Resources/en.lproj/Localizable.strings")
        let source = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"(?m)^\"((?:[^\"\\]|\\.)+)\"\s*="#)
        let range = NSRange(source.startIndex..., in: source)
        let keys = expression.matches(in: source, range: range).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        }
        #expect(Set(keys).count == keys.count)
    }

    @Test func englishIsTheSourceCatalogAndGermanIsComplete() throws {
        let english = try strings("en")
        let german = try strings("de")
        #expect(Set(english.keys) == Set(german.keys))

        let contextualEnglishValues: [String: String] = [
            "Preview Audio": "Preview",
            "Place Call": "Call",
            "Search Contacts Action": "Search Contacts",
            "Try another contact name or number.": "Try another name or number."
        ]
        for (key, value) in english {
            #expect(value == contextualEnglishValues[key, default: key])
        }
        #expect(german["Recents"] == "Anrufliste")
        #expect(german["Place Call"] == "Anrufen")
        #expect(german["Call"] == "Gespräch")
    }

    @Test func translatedFormatStringsPreserveEveryArgument() throws {
        let english = try strings("en")
        let german = try strings("de")
        for key in english.keys {
            #expect(try formatSpecifiers(in: english[key, default: ""])
                    == formatSpecifiers(in: german[key, default: ""]))
        }
    }

    private func formatSpecifiers(in value: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@diuoxXfFeEgGaAcCsSp]"#
        )
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let range = Range(match.range, in: value) else { return nil }
            return String(value[range]).replacingOccurrences(
                of: #"^%\d+\$"#,
                with: "%",
                options: .regularExpression
            )
        }
        .sorted()
    }

}
