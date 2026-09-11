import AppKit
import OSLog

enum MediaPlaybackPauser {
    private static let logger = Logger(subsystem: "de.enwikuna.TelefonX", category: "MediaPlayback")
    private static let supportedApplications = [
        (bundleID: "com.apple.Music", scriptName: "Music"),
        (bundleID: "com.spotify.client", scriptName: "Spotify")
    ]

    static func pausePlayingApplications() {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for application in supportedApplications where runningBundleIDs.contains(application.bundleID) {
            var error: NSDictionary?
            let source = "tell application \"\(application.scriptName)\" to if player state is playing then pause"
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                logger.error("Could not pause \(application.bundleID, privacy: .public); Apple event code=\(error[NSAppleScript.errorNumber] as? Int ?? -1, privacy: .public)")
            }
        }
    }
}
