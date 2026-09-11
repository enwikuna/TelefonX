import AppKit

@MainActor protocol MuteFeedbackPlaying {
    func play(muted: Bool, outputUID: String)
}

/// Short, familiar macOS feedback on the call output. The visual button state
/// remains the authoritative status for users who cannot or do not hear it.
@MainActor final class MuteFeedbackPlayer: MuteFeedbackPlaying {
    private var current: NSSound?

    func play(muted: Bool, outputUID: String) {
        current?.stop()
        guard let sound = NSSound(named: Self.soundName(muted: muted)) else { return }
        sound.playbackDeviceIdentifier = outputUID.isEmpty ? nil : outputUID
        sound.volume = 0.55
        current = sound
        _ = sound.play()
    }

    static func soundName(muted: Bool) -> NSSound.Name {
        NSSound.Name(muted ? "Pop" : "Tink")
    }
}
