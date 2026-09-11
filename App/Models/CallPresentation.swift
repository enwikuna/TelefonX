import Foundation
import TelefonDomain

enum CallPresentation {
    static func canSendTones(_ call: CallSession) -> Bool {
        call.phase == .connected && !call.held
    }

    static func pairedCall(for call: CallSession, in calls: [CallSession]) -> CallSession? {
        guard call.phase == .connected else { return nil }
        let active = calls.filter { $0.phase != .ended }
        guard active.count == 2,
              let other = active.first(where: { $0.handle != call.handle }),
              other.phase == .connected else { return nil }
        return other
    }

    static func selected(in calls: [CallSession], preferred: CallHandle?) -> CallSession? {
        let active = calls.filter { $0.phase != .ended }
        return active.first { $0.handle == preferred }
            ?? active.first { $0.incoming && $0.answeredAt == nil }
            ?? active.first { $0.phase == .connected && !$0.held }
            ?? active.first
    }

    static func status(_ call: CallSession, inConference: Bool = false) -> String {
        if call.held { return L10n.text("On Hold") }
        if call.remoteHeld { return L10n.text("Held by Other Party") }
        if inConference, call.phase == .connected { return L10n.text(call.muted ? "Conference · Microphone Muted" : "In Conference") }
        switch call.phase {
        case .calling: return L10n.text("Calling …")
        case .incoming: return L10n.text("Incoming Call")
        case .ringing: return L10n.text(call.incoming ? "Incoming Call" : "Ringing …")
        case .connecting: return L10n.text("Connecting …")
        case .connected: return L10n.text(call.muted ? "Microphone Muted" : "In Call")
        case .ended: return L10n.text("Ended")
        }
    }
}
