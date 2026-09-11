// swift-tools-version: 6.0
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let sources = "Packages/TelefonCore/Sources/"
let package = Package(
    name: "TelefonX",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "TelefonX", targets: ["TelefonX"])],
    targets: [
        .target(name: "TelefonDomain", path: sources + "TelefonDomain"),
        .target(name: "TelefonData", dependencies: ["TelefonDomain"], path: sources + "TelefonData"),
        .target(name: "CTelephony", path: sources + "CTelephony", publicHeadersPath: "include",
                cxxSettings: [.unsafeFlags(["-I" + root + "/Vendor/Install/include"]),
                              .define("PJSUA_MAX_CALLS", to: "32"), .define("PJSUA_MAX_ACC", to: "32")],
                linkerSettings: [.unsafeFlags([root + "/Vendor/Install/lib/libTelefonSIP.a"]),
                                 .linkedFramework("AudioToolbox"), .linkedFramework("CoreAudio"),
                                 .linkedFramework("Security"), .linkedFramework("CoreFoundation"),
                                 .linkedFramework("AVFoundation"), .linkedFramework("Foundation"),
                                 .linkedFramework("Network"),
                                 .linkedLibrary("c++")]),
        .target(name: "TelefonTelephony", dependencies: ["TelefonDomain", "CTelephony"], path: sources + "TelefonTelephony"),
        .executableTarget(name: "TelefonX", dependencies: ["TelefonDomain", "TelefonData", "TelefonTelephony"],
                          path: "App", exclude: ["Resources"]),
        .testTarget(name: "TelefonDomainTests", dependencies: ["TelefonDomain"], path: "Packages/TelefonCore/Tests/TelefonDomainTests"),
        .testTarget(name: "TelefonDataTests", dependencies: ["TelefonData", "TelefonDomain"], path: "Packages/TelefonCore/Tests/TelefonDataTests"),
        .testTarget(name: "TelefonAppTests", dependencies: ["TelefonX", "TelefonDomain"], path: "Tests/App")
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
