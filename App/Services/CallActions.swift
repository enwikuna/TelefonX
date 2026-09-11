import AVFoundation
import OSLog
import TelefonDomain
import TelefonTelephony

private let audioRouteLogger = Logger(subsystem: "de.enwikuna.TelefonX", category: "AudioRoute")

extension PhoneModel {
    var selectedLineRedialRecord: CallRecord? {
        guard let selectedAccountID else { return nil }
        return snapshot.history
            .filter { !$0.incoming && $0.accountID == selectedAccountID }
            .max { $0.startedAt < $1.startedAt }
    }

    var hasRedialTarget: Bool {
        guard let remote = selectedLineRedialRecord?.remote else { return false }
        return (try? CallDestination(remote)) != nil
    }

    var redialAccessibilityLabel: String {
        guard let account = selectedAccount, let record = selectedLineRedialRecord else {
            return L10n.text("No Last Dialed Number for This Line")
        }
        return L10n.format("Insert Last Number Dialed on %@: %@",
                           account.name, displayName(record.remote))
    }

    var redialHelp: String {
        L10n.format("%@ (⌘↩)", redialAccessibilityLabel)
    }

    var canUseDialAction: Bool {
        if !dialText.isEmpty { return canDial }
        guard let record = selectedLineRedialRecord, let selectedAccountID,
              registrations[selectedAccountID] == .registered else { return false }
        return canCall(record.remote, preferredAccountID: selectedAccountID)
    }

    /// With an empty dialer, the first action prepares the latest outgoing call.
    /// A populated dialer places the call, deliberately requiring a second action.
    @discardableResult func performDialAction() async -> CallHandle? {
        if dialText.isEmpty {
            guard let record = selectedLineRedialRecord, let selectedAccountID,
                  registrations[selectedAccountID] == .registered,
                  canCall(record.remote, preferredAccountID: selectedAccountID) else { return nil }
            prepareDial(record.remote, accountID: selectedAccountID)
            return nil
        }
        return await dial()
    }

    func refreshDevices() async {
        do {
            let fresh = try await engine.audioDevices()
            if fresh != devices { devices = fresh }
            if !activeCalls.isEmpty {
                if !inputUID.isEmpty && !fresh.contains(where: { $0.id == inputUID && $0.inputChannels > 0 }) {
                    audioWarning = "The selected microphone was disconnected. Place the call on hold and reconnect audio."
                } else if !outputUID.isEmpty && !fresh.contains(where: { $0.id == outputUID && $0.outputChannels > 0 }) {
                    audioWarning = "The selected headphones were disconnected. Place the call on hold and reconnect audio."
                }
            }
        } catch { audioWarning = L10n.error(error) }
    }
    func activateAudio() async throws {
        guard await authorizeMicrophone() else { throw AppError.microphoneDenied }
        await refreshDevices()
        func index(_ uid: String, input: Bool) throws -> Int32 {
            // Resolve macOS' current default to a concrete PJSIP device. Passing
            // PJSIP's own -1/-2 defaults can select a different CoreAudio route.
            if uid.isEmpty {
                let systemUID = input ? AudioHardware.defaultInputUID() : AudioHardware.defaultOutputUID()
                if let device = devices.first(where: { $0.id == systemUID && (input ? $0.inputChannels > 0 : $0.outputChannels > 0) }) {
                    return device.engineIndex
                }
                // Hardware-free previews and service mocks deliberately have no
                // CoreAudio UID mapping; preserve their PJSIP default sentinel.
                return input ? -1 : -2
            }
            guard let device = devices.first(where: { $0.id == uid && (input ? $0.inputChannels > 0 : $0.outputChannels > 0) }) else {
                throw AppError.unavailableDevice(input ? "Microphone" : "Headphones")
            }
            return device.engineIndex
        }
        let input = try index(inputUID, input: true)
        let output = try index(outputUID, input: false)
        audioRouteLogger.info("Activating concrete audio devices input=\(input, privacy: .public) output=\(output, privacy: .public)")
        try await engine.setAudio(input: input, output: output)
        audioWarning = nil
    }
    @discardableResult func dial() async -> CallHandle? {
        let reminderID = preparedReminder(for: dialText)
        let handle = await startCall(to: dialText, preferredAccountID: selectedAccountID, consumesDraft: true)
        if let handle {
            associateReminder(reminderID, with: handle)
            preparedReminderID = nil
        } else if reminderID == nil {
            preparedReminderID = nil
        }
        return handle
    }

    func canCall(_ value: String, preferredAccountID: UUID?) -> Bool {
        guard ready, conferenceHandles.isEmpty, !callOperationPending, !outgoingCallsBlockedByConfiguration,
              let destination = try? CallDestination(value) else { return false }
        let available = Set(snapshot.accounts.filter { registrations[$0.id] == .registered }.map(\.id))
        return Routing.account(for: destination.value, rules: availableDialRules, available: available,
                               fallback: preferredAccountID ?? selectedAccountID) != nil
    }

    /// Explicit call actions never consume or overwrite the user's unrelated dialer draft.
    @discardableResult func callNumber(_ value: String, preferredAccountID: UUID?) async -> CallHandle? {
        await startCall(to: value, preferredAccountID: preferredAccountID ?? selectedAccountID, consumesDraft: false)
    }

    /// List actions either prepare the dialer or call immediately, according to
    /// the user's preference. During a call they always start a consultation.
    @discardableResult func performListCall(_ value: String, preferredAccountID: UUID?,
                                            allowsAutomaticStart: Bool = true) async -> CallHandle? {
        guard conferenceHandles.isEmpty else { report(AppError.conferenceInProgress); return nil }
        guard !activeCalls.isEmpty else {
            guard prepareDial(value, accountID: preferredAccountID) else { return nil }
            return automaticallyStartListCalls && allowsAutomaticStart ? await dial() : nil
        }
        return await callNumber(value, preferredAccountID: preferredAccountID)
    }

    private func startCall(to value: String, preferredAccountID: UUID?, consumesDraft: Bool) async -> CallHandle? {
        guard ready, !callOperationPending, !outgoingCallsBlockedByConfiguration else { return nil }
        callOperationPending = true; defer { callOperationPending = false }
        do {
            guard conferenceHandles.isEmpty else { throw AppError.conferenceInProgress }
            let destination = try CallDestination(value)
            let available = Set(snapshot.accounts.filter { registrations[$0.id] == .registered }.map(\.id))
            let routedID = Routing.account(for: destination.value, rules: availableDialRules,
                                            available: available, fallback: preferredAccountID)
            guard let account = snapshot.accounts.first(where: { $0.id == routedID }) else { throw AppError.noLine }
            do {
                beginSilentRegistrationVerification(for: account.id)
                defer { endSilentRegistrationVerification(for: account.id) }
                guard try await engine.verifyRegistration(account.id) else {
                    registrations[account.id] = .offline
                    throw AppError.lineUnavailable
                }
                registrations[account.id] = .registered
            } catch {
                if registrations[account.id] == .registered {
                    let code = (error as? EngineError)?.code ?? -1
                    registrations[account.id] = .failed(code)
                }
                dialTones.playCallFailure(outputUID: outputUID)
                throw error
            }
            try await activateAudio()
            // A consultation never mixes microphone audio into two remote calls.
            for call in activeCalls where call.phase == .connected && !call.held { try await engine.hold(call.handle, held: true) }
            var outgoingAccount = account
            if suppressCallerIDOnce { outgoingAccount.suppressCallerID = true }
            let handle = try await engine.call(destination, account: outgoingAccount)
            // This is a one-shot choice, but a validation or connectivity error
            // before a native call exists must not silently consume it.
            suppressCallerIDOnce = false
            if !finished.contains(handle) && !calls.contains(where: { $0.handle == handle }) {
                calls.append(CallSession(handle: handle, accountID: account.id, remote: destination.value, incoming: false, phase: .calling))
            }
            pauseExternalMediaIfNeeded(for: handle)
            if consumesDraft, dialText == value { dialText = "" }
            return handle
        } catch { report(error); if activeCalls.isEmpty { await engine.releaseAudio() } }
        return nil
    }

    private var availableDialRules: [DialRule] {
        purchases.access.permits(.dialingRules) ? snapshot.dialRules : []
    }
    func answer(_ call: CallSession) async {
        guard !callOperationPending else { return }
        callOperationPending = true; defer { callOperationPending = false }
        do {
            guard conferenceHandles.isEmpty else { throw AppError.conferenceInProgress }
            try await activateAudio()
            for other in activeCalls where other.handle != call.handle && other.phase == .connected && !other.held {
                try await engine.hold(other.handle, held: true)
            }
            try await engine.answer(call.handle)
            clearIncomingAlert(call.handle)
            pauseExternalMediaIfNeeded(for: call.handle)
        } catch { report(error) }
    }
    func hangup(_ call: CallSession) async {
        let decline = call.incoming && call.answeredAt == nil
        do {
            try await engine.hangup(call.handle, decline: decline)
            if decline {
                markIncomingDeclined(call.handle)
            }
        } catch let error as EngineError where error.code == EngineError.invalidOperationCode {
            receive(.call(call.handle, accountID: call.accountID, remote: call.remote,
                          incoming: call.incoming, phase: .ended, status: call.lastStatus))
        } catch { report(error) }
    }
    func mute(_ call: CallSession) async {
        do {
            try await engine.mute(call.handle, muted: !call.muted)
            if let index = calls.firstIndex(where: { $0.handle == call.handle }) {
                calls[index].muted = !call.muted
                muteFeedback.play(muted: calls[index].muted, outputUID: outputUID)
            }
        } catch { report(error) }
    }
    func hold(_ call: CallSession) async {
        guard !callOperationPending else { return }
        callOperationPending = true; defer { callOperationPending = false }
        do {
            // Resuming a participant of a local conference must restore that
            // participant's conference routes. The normal consultation rule
            // (hold every other active call) applies only outside a conference.
            if call.held && !conferenceHandles.contains(call.handle) {
                for other in activeCalls where other.handle != call.handle && other.phase == .connected && !other.held {
                    try await engine.hold(other.handle, held: true)
                }
            }
            try await engine.hold(call.handle, held: !call.held)
        } catch { report(error) }
    }
    func tone(_ digit: String, call: CallSession) async {
        do { try await engine.sendDTMF(digit, call: call.handle) } catch { report(error) }
    }
    func transfer(_ source: CallSession, consultation: CallSession) async {
        do { try await engine.transfer(source.handle, to: consultation.handle) } catch { report(error) }
    }

    func startConference(_ first: CallSession, with second: CallSession) async {
        guard !callOperationPending, first.handle != second.handle,
              let currentFirst = activeCalls.first(where: { $0.handle == first.handle }),
              let currentSecond = activeCalls.first(where: { $0.handle == second.handle }),
              currentFirst.phase == .connected, currentSecond.phase == .connected,
              conferenceHandles.isEmpty else { return }
        callOperationPending = true
        defer { callOperationPending = false }
        let resumed = [currentFirst, currentSecond].filter(\.held)
        do {
            for call in resumed { try await engine.hold(call.handle, held: false) }
            try await engine.conference(currentFirst.handle, with: currentSecond.handle, enabled: true)
            conferenceHandles = [currentFirst.handle, currentSecond.handle]
        } catch {
            for call in resumed.reversed() { try? await engine.hold(call.handle, held: true) }
            conferenceHandles.removeAll()
            report(error)
        }
    }

    func endConference(keeping call: CallSession) async {
        guard !callOperationPending, conferenceHandles.contains(call.handle),
              let otherHandle = conferenceHandles.first(where: { $0 != call.handle }) else { return }
        callOperationPending = true
        defer { callOperationPending = false }
        do {
            try await engine.conference(call.handle, with: otherHandle, enabled: false)
            conferenceHandles.removeAll()
            if let other = activeCalls.first(where: { $0.handle == otherHandle }), !other.held {
                try await engine.hold(other.handle, held: true)
            }
        } catch { report(error) }
    }
}
