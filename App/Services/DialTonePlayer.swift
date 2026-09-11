import AVFAudio
import OSLog

@MainActor protocol DialTonePlaying {
    func play(_ digit: Character, outputUID: String)
    func playCallFailure(outputUID: String)
    func stop()
}

/// Output-only: no capture device, microphone permission or SIP operation.
@MainActor final class DialTonePlayer: DialTonePlaying {
    private var players: [Character: AVAudioPlayer] = [:]
    private var callFailurePlayer: AVAudioPlayer?
    private var current: AVAudioPlayer?
    private let logger = Logger(subsystem: "de.enwikuna.TelefonX", category: "KeypadAudio")
    func play(_ digit: Character, outputUID: String) {
        guard DialTone.frequencies(for: digit) != nil else { return }
        do {
            let player: AVAudioPlayer
            if let cached = players[digit] { player = cached }
            else {
                guard let data = DialTone.waveData(for: digit) else { return }
                player = try AVAudioPlayer(data: data, fileTypeHint: "wav")
                players[digit] = player
            }
            current?.stop()
            player.currentDevice = outputUID.isEmpty ? nil : outputUID
            player.currentTime = 0
            current = player
            if player.play() { logger.debug("Local keypad feedback started") }
            else { logger.error("Local keypad output unavailable") }
        } catch {
            // Never log digits, destinations or device identifiers.
            logger.error("Local keypad sound could not be prepared")
        }
    }
    func playCallFailure(outputUID: String) {
        do {
            let player: AVAudioPlayer
            if let callFailurePlayer { player = callFailurePlayer }
            else {
                player = try AVAudioPlayer(data: DialTone.callFailureWaveData(), fileTypeHint: "wav")
                callFailurePlayer = player
            }
            current?.stop()
            player.currentDevice = outputUID.isEmpty ? nil : outputUID
            player.currentTime = 0
            current = player
            if !player.play() { logger.error("Local call failure sound output unavailable") }
        } catch {
            logger.error("Local call failure sound could not be prepared")
        }
    }
    func stop() { current?.stop(); current = nil }
}
