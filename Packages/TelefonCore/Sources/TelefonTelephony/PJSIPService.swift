import Foundation
import CTelephony
import TelefonDomain

/// C events are copied synchronously. No C-owned string escapes the callback.
private final class EventSink: @unchecked Sendable {
    let continuation: AsyncStream<TelephonyEvent>.Continuation
    private let lock = NSLock()
    private var registrationProbes: [UUID: [UUID: AsyncStream<RegistrationState>.Continuation]] = [:]
    private var callAccounts: [CallHandle: UUID] = [:]
    init(_ continuation: AsyncStream<TelephonyEvent>.Continuation) { self.continuation = continuation }
    func registrationProbe(for accountID: UUID) -> AsyncStream<RegistrationState> {
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { probe in
            lock.withLock { registrationProbes[accountID, default: [:]][token] = probe }
            probe.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.registrationProbes[accountID]?[token] = nil
                    if self?.registrationProbes[accountID]?.isEmpty == true {
                        self?.registrationProbes[accountID] = nil
                    }
                }
            }
        }
    }
    func cancelRegistrationProbes(for accountID: UUID) {
        let probes = lock.withLock { registrationProbes.removeValue(forKey: accountID)?.values.map { $0 } ?? [] }
        for probe in probes { probe.finish() }
    }
    func receive(_ event: tx_event) {
        let handle = CallHandle(slot: event.call.slot, generation: event.call.generation)
        switch event.kind {
        case 1:
            guard let raw = event.account, let id = UUID(uuidString: String(cString: raw)) else { return }
            let state: RegistrationState
            if event.state != 0 { state = .registered }
            else if (100..<200).contains(event.status) { state = .registering }
            else if event.status == 0 || event.status == 200 { state = .offline }
            else { state = .failed(Int(event.status)) }
            continuation.yield(.registration(id, state))
            if state != .registering {
                let probes = lock.withLock { registrationProbes.removeValue(forKey: id)?.values.map { $0 } ?? [] }
                for probe in probes { probe.yield(state); probe.finish() }
            }
        case 2:
            let phases: [Int32: CallPhase] = [1: .calling, 2: .incoming, 3: .ringing, 4: .connecting, 5: .connected, 6: .ended]
            guard let phase = phases[event.state] else { return }
            let suppliedID = event.account.flatMap { UUID(uuidString: String(cString: $0)) }
            guard let id = lock.withLock({
                if let suppliedID { callAccounts[handle] = suppliedID }
                let result = suppliedID ?? callAccounts[handle]
                if phase == .ended { callAccounts[handle] = nil }
                return result
            }) else { return }
            let remote = event.remote.map { String(cString: $0) } ?? "Unbekannt"
            continuation.yield(.call(handle, accountID: id, remote: CallDestination.remoteAddress(from: remote),
                                     incoming: event.incoming != 0, phase: phase, status: Int(event.status)))
        case 3: continuation.yield(.media(handle, held: event.held != 0, remoteHeld: event.remote_held != 0, error: Int(event.status)))
        case 4: continuation.yield(.transfer(handle, status: Int(event.status), final: event.final != 0))
        case 5: continuation.yield(.failure(Int(event.status)))
        default: break
        }
    }
}

/// Public commands are serialized by this actor; the C++ layer confines PJLIB
/// calls to its registered worker thread. Exactly one live instance per process.
public actor PJSIPService: TelephonyService {
    public nonisolated let events: AsyncStream<TelephonyEvent>
    private let sink: EventSink
    private var started = false
    public init() {
        let pair = AsyncStream<TelephonyEvent>.makeStream()
        events = pair.stream; sink = EventSink(pair.continuation)
    }
    public func start() throws {
        guard !started else { return }
        let pointer = Unmanaged.passUnretained(sink).toOpaque()
        try check(tx_start({ event, context in
            guard let event, let context else { return }
            Unmanaged<EventSink>.fromOpaque(context).takeUnretainedValue().receive(event.pointee)
        }, pointer, 0, 0), "SIP-Engine starten")
        started = true
    }
    public func stop() { if started { tx_stop(); started = false }; sink.continuation.finish() }

    public func register(_ account: PhoneAccount, password: String) throws {
        try account.validate()
        guard password.utf8.count <= 4096, !password.utf8.contains(0) else { throw ValidationError.invalidAccount }
        // Keep every allocation alive until the synchronous native operation completes.
        let strings = try [account.id.uuidString, account.username, account.authenticationName, password,
                           account.domain, account.registrar, account.proxy, account.stunServer].map { value in
            guard let duplicate = value.withCString({ strdup($0) }) else {
                throw POSIXError(.ENOMEM)
            }
            return duplicate
        }
        defer { strings.forEach { free($0) } }
        var config = tx_account()
        config.uuid = UnsafePointer(strings[0]); config.username = UnsafePointer(strings[1])
        config.authname = UnsafePointer(strings[2]); config.password = UnsafePointer(strings[3])
        config.domain = UnsafePointer(strings[4]); config.registrar = UnsafePointer(strings[5])
        config.proxy = UnsafePointer(strings[6]); config.stun = UnsafePointer(strings[7])
        config.transport = account.transport == .tls ? 2 : (account.transport == .tcp ? 1 : 0)
        config.srtp = account.requireSRTP ? 1 : 0; config.ice = account.useICE ? 1 : 0
        config.g711_only = account.g711Only ? 1 : 0; config.interval = Int32(account.registrationInterval)
        try check(tx_add_account(&config), "Leitung anmelden")
    }
    public func unregister(_ id: UUID) throws { try check(tx_remove_account(id.uuidString), "Leitung abmelden") }
    public func verifyRegistration(_ id: UUID) async throws -> Bool {
        let probe = sink.registrationProbe(for: id)
        do { try check(tx_refresh_account(id.uuidString), "Leitung prüfen") }
        catch {
            sink.cancelRegistrationProbes(for: id)
            throw error
        }
        return await withTaskGroup(of: RegistrationState?.self) { group in
            group.addTask {
                for await state in probe { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result == .registered
        }
    }
    public func call(_ destination: CallDestination, account: PhoneAccount) throws -> CallHandle {
        var result = tx_call()
        try check(tx_make_call(account.id.uuidString, try destination.uri(for: account),
                               account.suppressCallerID ? 1 : 0, &result), "Anrufen")
        return CallHandle(slot: result.slot, generation: result.generation)
    }
    public func answer(_ call: CallHandle) throws { try check(tx_answer(native(call)), "Annehmen") }
    public func hangup(_ call: CallHandle, decline: Bool) throws { try check(tx_hangup(native(call), decline ? 1 : 0), "Auflegen") }
    public func mute(_ call: CallHandle, muted: Bool) throws { try check(tx_mute(native(call), muted ? 1 : 0), "Mikrofon schalten") }
    public func hold(_ call: CallHandle, held: Bool) async throws {
        try check(tx_hold(native(call), held ? 1 : 0), "Halten")
        // Await negotiated hold before consultation/answer can open another microphone path.
        for _ in 0..<100 {
            var actual: Int32 = 0, pending: Int32 = 0
            try check(tx_hold_status(native(call), &actual, &pending), "Halten bestätigen")
            if pending == 0 && (actual != 0) == held { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw EngineError(408, operation: "Halten bestätigen")
    }
    public func setHoldMusic(_ file: URL?) throws {
        try check(tx_set_hold_music(file?.path ?? ""), "Haltemusik einstellen")
    }
    public func sendDTMF(_ digit: String, call: CallHandle) throws {
        guard !digit.isEmpty, digit.count <= 32, digit.allSatisfy({ "0123456789*#ABCD".contains($0) }) else { throw ValidationError.invalidDestination }
        try check(tx_dtmf(native(call), digit), "Tastenton senden")
    }
    public func conference(_ first: CallHandle, with second: CallHandle, enabled: Bool) throws {
        try check(tx_conference(native(first), native(second), enabled ? 1 : 0),
                  enabled ? "Konferenz starten" : "Konferenz beenden")
    }
    public func transfer(_ source: CallHandle, to consultation: CallHandle) throws {
        try check(tx_transfer(native(source), native(consultation)), "Gespräche verbinden")
    }
    public func quality(_ call: CallHandle) throws -> CallQuality {
        var result = tx_quality()
        try check(tx_get_quality(native(call), &result), "Audioqualität lesen")
        let codec = decodeCString(result.codec)
        return CallQuality(codec: codec, clockRate: Int(result.clock_rate), receivedPackets: result.rx_packets,
                           lostPackets: result.lost_packets, jitterMilliseconds: result.jitter_ms,
                           roundTripMilliseconds: result.rtt_ms, secureMedia: result.srtp != 0)
    }
    public func audioDevices() throws -> [AudioDevice] {
        var devices = [tx_audio_device](repeating: tx_audio_device(), count: 128), count: Int32 = 0
        try check(tx_audio_devices(&devices, 128, &count), "Audiogeräte lesen")
        let hardware = AudioHardware.devices()
        return devices.prefix(Int(count)).compactMap { item in
            let name = decodeCString(item.name)
            let candidates = hardware.filter {
                $0.name == name
                    && (item.inputs == 0 || $0.hasInput)
                    && (item.outputs == 0 || $0.hasOutput)
            }
            // Bluetooth headsets commonly expose distinct input/output devices
            // with the same name. Direction makes that mapping unambiguous.
            guard candidates.count == 1 else { return nil }
            return AudioDevice(id: candidates[0].uid, name: name, inputChannels: Int(item.inputs),
                               outputChannels: Int(item.outputs), engineIndex: item.index)
        }
    }
    public func setAudio(input: Int32, output: Int32) throws { try check(tx_set_audio(input, output), "Audiogeräte öffnen") }
    public func releaseAudio() { _ = tx_release_audio() }
    public func networkChanged() throws { try check(tx_network_changed(), "Netzwerkverbindung erneuern") }
    private func native(_ value: CallHandle) -> tx_call { tx_call(slot: value.slot, generation: value.generation) }
    private func check(_ status: Int32, _ operation: String) throws {
        if status != 0 { throw EngineError(Int(status), operation: operation) }
    }
}

private func decodeCString<Value>(_ value: Value) -> String {
    withUnsafeBytes(of: value) { bytes in
        guard let baseAddress = bytes.baseAddress else { return "" }
        return String(cString: baseAddress.assumingMemoryBound(to: CChar.self))
    }
}
