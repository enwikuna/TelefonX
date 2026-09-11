import Foundation

public enum CallPhase: String, Codable, Sendable {
    case calling, incoming, ringing, connecting, connected, ended
    public func permits(_ next: CallPhase) -> Bool {
        if self == next { return true }
        if self == .ended { return false }
        if next == .ended { return true }
        switch self {
        case .calling: return [.ringing, .connecting, .connected].contains(next)
        case .incoming: return [.ringing, .connecting, .connected].contains(next)
        case .ringing: return [.connecting, .connected].contains(next)
        case .connecting: return next == .connected
        case .connected, .ended: return false
        }
    }
}

public struct CallHandle: Hashable, Sendable {
    public let slot: Int32
    public let generation: UInt64
    public init(slot: Int32, generation: UInt64) { self.slot = slot; self.generation = generation }
}

public struct CallSession: Identifiable, Sendable {
    public let id: UUID
    public let handle: CallHandle
    public let accountID: UUID
    public let remote: String
    public let incoming: Bool
    public var phase: CallPhase
    public var muted = false
    public var held = false
    public var remoteHeld = false
    public let startedAt: Date
    public var answeredAt: Date?
    public var endedAt: Date?
    public var locallyDeclined = false
    public var blocked = false
    public var lastStatus = 0
    public var mediaError = 0
    public var quality: CallQuality?

    public init(id: UUID = UUID(), handle: CallHandle, accountID: UUID, remote: String, incoming: Bool,
                phase: CallPhase, startedAt: Date = Date()) {
        self.id = id; self.handle = handle; self.accountID = accountID; self.remote = remote
        self.incoming = incoming; self.phase = phase; self.startedAt = startedAt
    }

    @discardableResult public mutating func transition(to next: CallPhase, at date: Date = Date()) -> Bool {
        guard phase.permits(next) else { return false }
        phase = next
        if next == .connected && answeredAt == nil { answeredAt = date }
        if next == .ended && endedAt == nil { endedAt = date }
        return true
    }
}

public struct CallQuality: Equatable, Sendable {
    public var codec: String
    public var clockRate: Int
    public var receivedPackets: UInt32
    public var lostPackets: UInt32
    public var jitterMilliseconds: Double
    public var roundTripMilliseconds: Double
    public var secureMedia: Bool
    public init(codec: String, clockRate: Int, receivedPackets: UInt32, lostPackets: UInt32,
                jitterMilliseconds: Double, roundTripMilliseconds: Double, secureMedia: Bool) {
        self.codec = codec; self.clockRate = clockRate; self.receivedPackets = receivedPackets
        self.lostPackets = lostPackets; self.jitterMilliseconds = jitterMilliseconds
        self.roundTripMilliseconds = roundTripMilliseconds; self.secureMedia = secureMedia
    }
    public var lossPercent: Double {
        let total = Double(receivedPackets) + Double(lostPackets)
        return total > 0 ? 100 * Double(lostPackets) / total : 0
    }
}
