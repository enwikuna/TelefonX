import Foundation
import Testing

@Suite struct PrivacyManifestTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func manifestDeclaresNoTrackingOrDeveloperDataCollection() throws {
        let url = repository.appending(path: "App/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let manifest = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.isEmpty == true)
        #expect((manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])?.isEmpty == true)
        #expect(Set(manifest.keys) == [
            "NSPrivacyTracking",
            "NSPrivacyTrackingDomains",
            "NSPrivacyCollectedDataTypes",
            "NSPrivacyAccessedAPITypes"
        ])
    }

    @Test func productionBuildEmbedsAndValidatesTheManifest() throws {
        let script = try String(
            contentsOf: repository.appending(path: "script/build_and_run.sh"),
            encoding: .utf8
        )

        #expect(script.contains("App/Resources/PrivacyInfo.xcprivacy"))
        #expect(script.contains("$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"))
    }
}
