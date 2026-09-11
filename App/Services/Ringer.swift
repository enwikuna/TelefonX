import AppKit
import Observation
import UserNotifications
import TelefonDomain

@MainActor @Observable final class SoundPlayback {
    static let ringtonePause: Duration = .milliseconds(1_500)
    private(set) var isPlaying = false
    @ObservationIgnored private var sound: NSSound?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    func play(_ url: URL, outputUID: String, looping: Bool) throws {
        stop()
        guard let sound = NSSound(contentsOf: url, byReference: true) else { throw SoundError.unsupported }
        // NSSound's native loop restarts at the final sample and provides no
        // ringtone cadence. Repeat manually so every tone has a clear pause.
        sound.loops = false; sound.volume = 0.6
        sound.playbackDeviceIdentifier = outputUID.isEmpty ? nil : outputUID
        guard sound.play() else { throw SoundError.unsupported }
        self.sound = sound; isPlaying = true
        let duration = Duration.seconds(min(max(sound.duration, 0.2), 600))
        endTask = Task { [weak self, weak sound] in
            repeat {
                do { try await Task.sleep(for: duration) } catch { return }
                guard !Task.isCancelled, let self, let sound, self.sound === sound else { return }
                if !looping { self.stop(); return }
                do { try await Task.sleep(for: Self.ringtonePause) } catch { return }
                guard !Task.isCancelled, self.sound === sound else { return }
                sound.currentTime = 0
                guard sound.play() else { self.stop(); return }
            } while looping
            }
    }
    func stop() { endTask?.cancel(); endTask = nil; sound?.stop(); sound = nil; isPlaying = false }
    func setOutput(_ uid: String) { sound?.playbackDeviceIdentifier = uid.isEmpty ? nil : uid }
}

@MainActor final class Ringer {
    var outputUID = "" { didSet { playback.setOutput(outputUID) } }
    private let playback = SoundPlayback()
    private var current: CallHandle?
    private var currentTone: LineRingtone?
    private let library: AudioFileStore
    init(library: AudioFileStore = AudioFileStore()) { self.library = library }

    func update(calls: [CallSession], accounts: [PhoneAccount]) {
        guard let call = RingtoneRouting.incoming(in: calls) else { stop(); return }
        let tone = RingtoneRouting.sound(for: call, accounts: accounts)
        guard current != call.handle || currentTone != tone || !playback.isPlaying else { return }
        stop(); current = call.handle; currentTone = tone
        do { try playback.play(Self.url(for: tone, library: library), outputUID: outputUID, looping: true) }
        catch {
            // A missing imported file must never silence an incoming call.
            try? playback.play(Self.url(for: .system(.glass), library: library), outputUID: outputUID, looping: true)
        }
    }
    static func url(for tone: LineRingtone, library: AudioFileStore) -> URL {
        switch tone {
        case .system(let sound): URL(fileURLWithPath: "/System/Library/Sounds/\(sound.rawValue).aiff")
        case .file(let asset): library.url(for: asset)
        }
    }
    func stop() { playback.stop(); current = nil; currentTone = nil }
}

enum IncomingNotifications {
    enum Authorization: Equatable, Sendable {
        case unknown, notDetermined, denied, allowed

        var label: String {
            switch self {
            case .unknown: L10n.text("Loading …")
            case .notDetermined: L10n.text("Not Set Up Yet")
            case .denied: L10n.text("Not Allowed")
            case .allowed: L10n.text("Allowed")
            }
        }
    }

    static func authorization() async -> Authorization {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default: return .unknown
        }
    }

    @discardableResult
    static func request() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    static func post(name: String, line: String, id: CallHandle) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text("Incoming Call"); content.body = "\(name) · \(line)"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key(id), content: content, trigger: nil))
    }
    static func remove(_ id: CallHandle) { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [key(id)]) }
    private static func key(_ id: CallHandle) -> String { "call.\(id.slot).\(id.generation)" }
}

/// Requests the native Dock attention animation for unanswered calls. The
/// system stops the animation when the user activates TelefonX; these tokens
/// additionally let us cancel it when the call ends without user interaction.
@MainActor enum IncomingCallAttention {
    private static var waiting = Set<CallHandle>()
    private static var requestID: Int?

    static func request(_ handle: CallHandle) {
        waiting.insert(handle)
        guard !NSApp.isActive, requestID == nil else { return }
        requestID = NSApp.requestUserAttention(.criticalRequest)
    }

    static func cancel(_ handle: CallHandle) {
        waiting.remove(handle)
        guard waiting.isEmpty, let requestID else { return }
        NSApp.cancelUserAttentionRequest(requestID)
        self.requestID = nil
    }

    static func cancelAll() {
        waiting.removeAll()
        if let requestID { NSApp.cancelUserAttentionRequest(requestID) }
        requestID = nil
    }
}
