import Observation
import OSLog
import TelefonDomain
import TelefonData
import TelefonTelephony

private func registrationStates(
    for accounts: [PhoneAccount],
    engine: any TelephonyService
) async -> [(UUID, RegistrationState)] {
    await withTaskGroup(of: (UUID, RegistrationState).self) { group in
        for account in accounts {
            group.addTask {
                do {
                    return (account.id, try await engine.verifyRegistration(account.id)
                            ? .registered : .failed(408))
                } catch {
                    return (account.id, .failed((error as? EngineError)?.code ?? -1))
                }
            }
        }
        var states: [(UUID, RegistrationState)] = []
        for await state in group { states.append(state) }
        return states
    }
}

@MainActor @Observable final class PhoneModel {
    var snapshot = AppSnapshot()
    var registrations: [UUID: RegistrationState] = [:]
    var calls: [CallSession] = []
    var conferenceHandles = Set<CallHandle>()
    var devices: [AudioDevice] = []
    var dialText = ""
    var suppressCallerIDOnce = false
    var selectedAccountID: UUID?
    var errorMessage: String?
    var information: String?
    var lastEndedCall: CallRecord?
    var ready = false
    var starting = false
    var callOperationPending = false
    var configurationBusy = false
    var storageError: String?
    var audioWarning: String?
    var holdMusicWarning: String?
    private(set) var manualDoNotDisturb: Bool
    private(set) var manualDoNotDisturbUntil: Date?
    private(set) var focusSyncEnabled: Bool
    private(set) var macFocusActive = false
    private(set) var pauseMediaDuringCalls: Bool
    private(set) var callWaitingEnabled: Bool
    private(set) var automaticallyStartListCalls: Bool
    private(set) var publicCallerLookupEnabled: Bool
    private(set) var defaultReminderNotificationTiming: CallReminderNotificationTiming
    private(set) var publicCallerNames: [String: String] = [:]
    private(set) var appleContactsEnabled: Bool
    private(set) var appleContactsAuthorization: AppleContactsAuthorization
    private(set) var appleContacts: [AppleContact] = []
    private(set) var appleContactsLoading = false
    private(set) var appleContactsError: String?
    private(set) var unseenMissedCallIDs: Set<UUID>
    var inputUID: String { didSet { UserDefaults.standard.set(inputUID, forKey: "audio.input") } }
    var outputUID: String { didSet { UserDefaults.standard.set(outputUID, forKey: "audio.output") } }
    var ringtoneUID: String { didSet { UserDefaults.standard.set(ringtoneUID, forKey: "audio.ringtone"); ringer.outputUID = ringtoneUID } }
    @ObservationIgnored let engine: any TelephonyService
    @ObservationIgnored let credentials: any CredentialStore
    @ObservationIgnored private(set) var repository: (any PhoneRepository)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var qualityTask: Task<Void, Never>?
    @ObservationIgnored private var registrationRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundRegistrationRecoveryActive = false
    @ObservationIgnored private var registrationHealthCheckActive = false
    @ObservationIgnored private var silentlyVerifiedAccounts = Set<UUID>()
    @ObservationIgnored private var pendingRegistrationStates: [UUID: RegistrationState] = [:]
    @ObservationIgnored private var pendingRegistrationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var doNotDisturbExpirationTask: Task<Void, Never>?
    @ObservationIgnored let ringer: Ringer
    @ObservationIgnored let audioFiles: AudioFileStore
    @ObservationIgnored let dialTones: any DialTonePlaying
    @ObservationIgnored let muteFeedback: any MuteFeedbackPlaying
    @ObservationIgnored let publicCallerLookup: any PublicCallerLookingUp
    @ObservationIgnored let appleContactsProvider: any AppleContactsProviding
    @ObservationIgnored private let persistDoNotDisturb: (Bool) -> Void
    @ObservationIgnored private let persistDoNotDisturbUntil: (Date?) -> Void
    @ObservationIgnored private let currentDate: () -> Date
    @ObservationIgnored private let persistFocusSyncEnabled: (Bool) -> Void
    @ObservationIgnored private let persistPauseMediaDuringCalls: (Bool) -> Void
    @ObservationIgnored private let persistCallWaitingEnabled: (Bool) -> Void
    @ObservationIgnored private let persistAutomaticallyStartListCalls: (Bool) -> Void
    @ObservationIgnored private let persistPublicCallerLookupEnabled: (Bool) -> Void
    @ObservationIgnored private let persistReminderNotificationTiming: (CallReminderNotificationTiming) -> Void
    @ObservationIgnored private let persistAppleContactsEnabled: (Bool) -> Void
    @ObservationIgnored private let persistUnseenMissedCallIDs: (Set<UUID>) -> Void
    @ObservationIgnored private let pauseMediaPlayback: () -> Void
    @ObservationIgnored private let postIncomingNotification: (String, String, CallHandle) -> Void
    @ObservationIgnored private let removeIncomingNotification: (CallHandle) -> Void
    @ObservationIgnored let scheduleReminderNotification: @Sendable (CallReminder, CallReminderNotificationTiming, Bool) async throws -> Void
    @ObservationIgnored let removeReminderNotification: @Sendable (UUID) -> Void
    @ObservationIgnored private let requestIncomingAttention: (CallHandle) -> Void
    @ObservationIgnored private let cancelIncomingAttention: (CallHandle) -> Void
    @ObservationIgnored let authorizeMicrophone: @Sendable () async -> Bool
    @ObservationIgnored let purchases: PurchaseStore
    @ObservationIgnored var finished = Set<CallHandle>()
    @ObservationIgnored private var pendingMedia: [CallHandle: (Bool, Bool, Int)] = [:]
    @ObservationIgnored private var mediaPausedForCalls = Set<CallHandle>()
    @ObservationIgnored var preparedReminderID: UUID?
    @ObservationIgnored var reminderCalls: [CallHandle: UUID] = [:]
    @ObservationIgnored private var networkRefreshPending = false
    @ObservationIgnored private var networkRefreshInProgress = false
    @ObservationIgnored private var networkRefreshRequestedDuringRun = false
    @ObservationIgnored private var networkRefreshDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var resolvingPublicCallers = Set<String>()
    @ObservationIgnored private var publicCallerMisses = Set<String>()
    @ObservationIgnored private var appleContactsRefreshGeneration = 0
    @ObservationIgnored private var publicCallerLookupGeneration = 0
    @ObservationIgnored private let logger = Logger(subsystem: "de.enwikuna.TelefonX", category: "Lifecycle")

    init(engine: any TelephonyService = PJSIPService(), credentials: any CredentialStore = KeychainCredentials(),
         repository: (any PhoneRepository)? = nil, dialTones: any DialTonePlaying = DialTonePlayer(),
         muteFeedback: any MuteFeedbackPlaying = MuteFeedbackPlayer(),
         authorizeMicrophone: @escaping @Sendable () async -> Bool = MicrophoneAuthorization.request,
         audioFiles: AudioFileStore = AudioFileStore(), initialDoNotDisturb: Bool = false,
         persistDoNotDisturb: @escaping (Bool) -> Void = { _ in },
         initialDoNotDisturbUntil: Date? = nil,
         persistDoNotDisturbUntil: @escaping (Date?) -> Void = { _ in },
         currentDate: @escaping () -> Date = Date.init,
         postIncomingNotification: @escaping (String, String, CallHandle) -> Void = { _, _, _ in },
         removeIncomingNotification: @escaping (CallHandle) -> Void = { _ in },
         scheduleReminderNotification: @escaping @Sendable (CallReminder, CallReminderNotificationTiming, Bool) async throws -> Void = { _, _, _ in },
         removeReminderNotification: @escaping @Sendable (UUID) -> Void = { _ in },
         requestIncomingAttention: @escaping (CallHandle) -> Void = { _ in },
         cancelIncomingAttention: @escaping (CallHandle) -> Void = { _ in },
         initialPauseMediaDuringCalls: Bool = false, initialCallWaitingEnabled: Bool = true,
         persistPauseMediaDuringCalls: @escaping (Bool) -> Void = { _ in },
         persistCallWaitingEnabled: @escaping (Bool) -> Void = { _ in },
         initialAutomaticallyStartListCalls: Bool = false,
         persistAutomaticallyStartListCalls: @escaping (Bool) -> Void = { _ in },
         publicCallerLookup: any PublicCallerLookingUp = MapKitPublicCallerLookup(),
         initialPublicCallerLookupEnabled: Bool = false,
         persistPublicCallerLookupEnabled: @escaping (Bool) -> Void = { _ in },
         initialReminderNotificationTiming: CallReminderNotificationTiming = .atTime,
         persistReminderNotificationTiming: @escaping (CallReminderNotificationTiming) -> Void = { _ in },
         appleContactsProvider: any AppleContactsProviding = SystemAppleContactsProvider(),
         initialAppleContactsEnabled: Bool = false,
         initialAppleContacts: [AppleContact] = [],
         persistAppleContactsEnabled: @escaping (Bool) -> Void = { _ in },
         initialUnseenMissedCallIDs: Set<UUID> = [],
         persistUnseenMissedCallIDs: @escaping (Set<UUID>) -> Void = { _ in },
         initialFocusSyncEnabled: Bool = false,
         persistFocusSyncEnabled: @escaping (Bool) -> Void = { _ in },
         purchases: PurchaseStore = PurchaseStore(internalEvaluation: true, productIDs: []),
         pauseMediaPlayback: @escaping () -> Void = MediaPlaybackPauser.pausePlayingApplications) {
        self.engine = engine; self.credentials = credentials
        self.dialTones = dialTones
        self.muteFeedback = muteFeedback
        let validEnd = initialDoNotDisturbUntil.flatMap { $0 > currentDate() ? $0 : nil }
        let manualDoNotDisturb = initialDoNotDisturb && (initialDoNotDisturbUntil == nil || validEnd != nil)
        self.manualDoNotDisturb = manualDoNotDisturb
        self.manualDoNotDisturbUntil = manualDoNotDisturb ? validEnd : nil
        self.focusSyncEnabled = initialFocusSyncEnabled
        self.pauseMediaDuringCalls = initialPauseMediaDuringCalls
        self.callWaitingEnabled = initialCallWaitingEnabled
        self.automaticallyStartListCalls = initialAutomaticallyStartListCalls
        self.publicCallerLookup = publicCallerLookup
        self.publicCallerLookupEnabled = initialPublicCallerLookupEnabled
        self.defaultReminderNotificationTiming = initialReminderNotificationTiming
        self.appleContactsProvider = appleContactsProvider
        self.appleContactsEnabled = initialAppleContactsEnabled
        self.appleContacts = initialAppleContacts
        self.appleContactsAuthorization = appleContactsProvider.authorizationStatus()
        self.unseenMissedCallIDs = initialUnseenMissedCallIDs
        self.persistDoNotDisturb = persistDoNotDisturb
        self.persistDoNotDisturbUntil = persistDoNotDisturbUntil
        self.currentDate = currentDate
        self.persistFocusSyncEnabled = persistFocusSyncEnabled
        self.persistPauseMediaDuringCalls = persistPauseMediaDuringCalls
        self.persistCallWaitingEnabled = persistCallWaitingEnabled
        self.persistAutomaticallyStartListCalls = persistAutomaticallyStartListCalls
        self.persistPublicCallerLookupEnabled = persistPublicCallerLookupEnabled
        self.persistReminderNotificationTiming = persistReminderNotificationTiming
        self.persistAppleContactsEnabled = persistAppleContactsEnabled
        self.persistUnseenMissedCallIDs = persistUnseenMissedCallIDs
        self.pauseMediaPlayback = pauseMediaPlayback
        self.postIncomingNotification = postIncomingNotification
        self.removeIncomingNotification = removeIncomingNotification
        self.scheduleReminderNotification = scheduleReminderNotification
        self.removeReminderNotification = removeReminderNotification
        self.requestIncomingAttention = requestIncomingAttention
        self.cancelIncomingAttention = cancelIncomingAttention
        self.authorizeMicrophone = authorizeMicrophone
        self.purchases = purchases
        self.audioFiles = audioFiles; self.ringer = Ringer(library: audioFiles)
        inputUID = UserDefaults.standard.string(forKey: "audio.input") ?? ""
        outputUID = UserDefaults.standard.string(forKey: "audio.output") ?? ""
        ringtoneUID = UserDefaults.standard.string(forKey: "audio.ringtone") ?? ""
        ringer.outputUID = ringtoneUID
        self.purchases.onAccessChange = { [weak self] in
            Task { await self?.applyProAccessChange() }
        }
        do {
            if let repository {
                self.repository = repository; snapshot = try repository.load()
                selectedAccountID = snapshot.defaultAccountID.flatMap {
                    permittedAccountIDs.contains($0) ? $0 : nil
                } ?? snapshot.accounts.first?.id
                return
            }
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "TelefonX", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let repository = try SwiftDataRepository(url: base.appending(path: "TelefonX.store"))
            self.repository = repository; snapshot = try repository.load()
            selectedAccountID = snapshot.defaultAccountID.flatMap {
                permittedAccountIDs.contains($0) ? $0 : nil
            } ?? snapshot.accounts.first?.id
        } catch { storageError = L10n.error(error) }
    }
    var activeCalls: [CallSession] { calls.filter { $0.phase != .ended } }
    var doNotDisturb: Bool { focusSyncEnabled ? macFocusActive : manualDoNotDisturb }
    var canSetDoNotDisturbManually: Bool { !focusSyncEnabled }
    /// Calls that still exist in the SIP stack but should be shown as an
    /// interaction. Locally rejected and blocked INVITEs remain internal until
    /// their final SIP event arrives, so they must not flash in the call UI.
    var presentedCalls: [CallSession] {
        activeCalls.filter { !$0.locallyDeclined && !$0.blocked }
    }
    var registeredCount: Int {
        registrations.count { permittedAccountIDs.contains($0.key) && $0.value == .registered }
    }
    var selectedAccount: PhoneAccount? { snapshot.accounts.first { $0.id == selectedAccountID } }
    var visibleAppleContacts: [AppleContact] { Self.removingAppleDuplicates(appleContacts, local: snapshot.contacts) }
    var outgoingCallsBlockedByConfiguration: Bool {
        configurationBusy && !backgroundRegistrationRecoveryActive
    }
    var canDial: Bool { ready && !callOperationPending && !outgoingCallsBlockedByConfiguration && selectedAccount.map { registrations[$0.id] == .registered } == true && (try? CallDestination(dialText)) != nil }
    var selectedAccountAlwaysSuppressesCallerID: Bool { selectedAccount?.suppressCallerID == true }
    var callerIDSuppressionIsActive: Bool { selectedAccountAlwaysSuppressesCallerID || suppressCallerIDOnce }
    func isInConference(_ call: CallSession) -> Bool { conferenceHandles.contains(call.handle) }

    func toggleCallerIDSuppressionForNextCall() {
        guard !selectedAccountAlwaysSuppressesCallerID else { return }
        suppressCallerIDOnce.toggle()
    }

    func start() async {
        guard !starting, !ready, storageError == nil else { return }
        starting = true; defer { starting = false }
        scheduleDoNotDisturbExpiration()
        synchronizeReminderNotifications()
        if appleContactsEnabled {
            Task { [weak self] in await self?.refreshAppleContacts(requestAccess: true) }
        }
        if eventTask == nil {
            eventTask = Task { [weak self, engine] in
                for await event in engine.events { self?.receive(event) }
            }
        }
        do {
            try await engine.start(); ready = true
            if purchases.access.permits(.holdMusic), let music = snapshot.holdMusic {
                do {
                    guard audioFiles.exists(music) else { throw SoundError.missing }
                    try await engine.setHoldMusic(audioFiles.url(for: music))
                } catch { holdMusicWarning = "Hold music is unavailable. Choose it again under Audio." }
            }
            logger.notice("SIP engine ready")
            await refreshDevices()
            for account in snapshot.accounts { await register(account) }
            qualityTask = Task { [weak self] in
                var tick = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self else { break }
                    for call in self.activeCalls where call.phase == .connected {
                        if let quality = try? await self.engine.quality(call.handle),
                           let index = self.calls.firstIndex(where: { $0.handle == call.handle }) { self.calls[index].quality = quality }
                    }
                    tick += 1
                    if tick % 3 == 0 { await self.refreshDevices() }
                }
            }
            registrationRecoveryTask = Task { [weak self] in
                var tick = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled, let self else { break }
                    tick += 1
                    if tick % 4 == 0 { await self.verifyRegisteredAccounts() }
                    await self.recoverUnavailableRegistrations()
                }
            }
        } catch { report(error) }
    }
    func shutdown() async {
        logger.notice("Graceful shutdown requested")
        ready = false
        qualityTask?.cancel()
        registrationRecoveryTask?.cancel()
        networkRefreshDebounceTask?.cancel()
        pendingRegistrationTasks.values.forEach { $0.cancel() }
        pendingRegistrationTasks.removeAll()
        pendingRegistrationStates.removeAll()
        doNotDisturbExpirationTask?.cancel()
        ringer.stop(); dialTones.stop()
        for call in activeCalls where call.incoming { cancelIncomingAttention(call.handle) }
        mediaPausedForCalls.removeAll()
        purchases.stop()
        await engine.stop()
        // stop() finishes the stream after native teardown. Drain buffered final
        // events before terminating, otherwise their history writes can be lost.
        await eventTask?.value
        eventTask = nil
    }
    func register(_ account: PhoneAccount, showsProgress: Bool = true) async {
        guard ready else { return }
        guard !isAccountLockedByPro(account.id) else {
            cancelPendingRegistrationState(for: account.id)
            registrations[account.id] = .disabled
            return
        }
        guard account.enabled else { registrations[account.id] = .disabled; return }
        if showsProgress { showRegistrationProgress(for: account.id) }
        do {
            guard let password = try credentials.password(for: account.id), !password.isEmpty else {
                cancelPendingRegistrationState(for: account.id)
                registrations[account.id] = .failed(401)
                return
            }
            try await engine.register(account, password: password)
        } catch {
            let code = (error as? EngineError)?.code ?? -1
            cancelPendingRegistrationState(for: account.id)
            registrations[account.id] = .failed(code)
            logger.error("SIP registration failed; engine code: \(code, privacy: .public)")
        }
    }
    /// Rebuilds SIP registrations so DNS, routes and connection-oriented
    /// transports are resolved again. This is intentionally limited to idle
    /// periods because replacing an account would also affect its calls.
    func reconnect(accountID: UUID? = nil) async {
        guard ready else { await start(); return }
        let accounts = snapshot.accounts.filter {
            $0.enabled && !isAccountLockedByPro($0.id) && (accountID == nil || $0.id == accountID)
        }
        await rebuildRegistrations(accounts, reportFailure: true)
    }

    func scheduleNetworkRefresh() {
        networkRefreshDebounceTask?.cancel()
        networkRefreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            networkRefreshDebounceTask = nil
            await networkDidChange()
        }
    }

    func networkDidChange() async {
        guard ready else { return }
        guard !networkRefreshInProgress else {
            networkRefreshRequestedDuringRun = true
            return
        }
        guard activeCalls.isEmpty else {
            networkRefreshPending = true
            logger.notice("Deferring SIP network refresh while a call is active")
            return
        }
        guard !registrationHealthCheckActive else {
            scheduleNetworkRefresh()
            return
        }
        networkRefreshPending = false
        networkRefreshInProgress = true
        defer {
            networkRefreshInProgress = false
            if networkRefreshRequestedDuringRun {
                networkRefreshRequestedDuringRun = false
                scheduleNetworkRefresh()
            }
        }
        do {
            try await engine.networkChanged()
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard ready else { return }
            let newlyUnavailable = await verifyRegisteredAccounts(publishesFailures: false)
            let unavailable = snapshot.accounts.filter {
                $0.enabled && !isAccountLockedByPro($0.id)
                    && (registrations[$0.id] != .registered || newlyUnavailable.contains($0.id))
            }
            await rebuildRegistrations(unavailable, reportFailure: false)
        } catch {
            logger.error("SIP network refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult func verifyRegisteredAccounts(publishesFailures: Bool = true) async -> Set<UUID> {
        guard ready, activeCalls.isEmpty, !callOperationPending, !configurationBusy,
              !registrationHealthCheckActive else { return [] }
        let accounts = snapshot.accounts.filter {
            $0.enabled && !isAccountLockedByPro($0.id) && registrations[$0.id] == .registered
        }
        guard !accounts.isEmpty else { return [] }
        registrationHealthCheckActive = true
        defer { registrationHealthCheckActive = false }
        let accountIDs = Set(accounts.map(\.id))
        silentlyVerifiedAccounts.formUnion(accountIDs)
        defer { silentlyVerifiedAccounts.subtract(accountIDs) }
        let results = await registrationStates(for: accounts, engine: engine)
        let unavailable = Set(results.compactMap { id, state in state == .registered ? nil : id })
        for (id, state) in results where state == .registered || publishesFailures {
            registrations[id] = state
        }
        return unavailable
    }

    func beginSilentRegistrationVerification(for id: UUID) {
        silentlyVerifiedAccounts.insert(id)
    }

    func endSilentRegistrationVerification(for id: UUID) {
        silentlyVerifiedAccounts.remove(id)
    }

    private func recoverUnavailableRegistrations() async {
        guard ready, activeCalls.isEmpty, !callOperationPending, !configurationBusy else { return }
        let unavailable = snapshot.accounts.filter { account in
            guard account.enabled, !isAccountLockedByPro(account.id) else { return false }
            return switch registrations[account.id] ?? .offline {
            case .failed, .offline: true
            case .disabled, .registering, .registered: false
            }
        }
        guard !unavailable.isEmpty else { return }
        logger.notice("Retrying \(unavailable.count, privacy: .public) unavailable SIP registration(s)")
        await rebuildRegistrations(unavailable, reportFailure: false, showsProgress: false)
    }

    private func rebuildRegistrations(_ accounts: [PhoneAccount], reportFailure: Bool,
                                      showsProgress: Bool = true) async {
        guard !accounts.isEmpty else { return }
        guard activeCalls.isEmpty, !callOperationPending, !configurationBusy else {
            logger.notice("Skipping SIP registration rebuild while telephony is busy")
            return
        }
        if !showsProgress { backgroundRegistrationRecoveryActive = true }
        configurationBusy = true
        defer {
            configurationBusy = false
            backgroundRegistrationRecoveryActive = false
        }
        for account in accounts {
            if !showsProgress && !activeCalls.isEmpty { break }
            if showsProgress { showRegistrationProgress(for: account.id) }
            do {
                try await engine.unregister(account.id)
                await register(account, showsProgress: showsProgress)
            } catch {
                let code = (error as? EngineError)?.code ?? -1
                cancelPendingRegistrationState(for: account.id)
                registrations[account.id] = .failed(code)
                logger.error("SIP registration rebuild failed; engine code: \(code, privacy: .public)")
                if reportFailure { report(error) }
            }
        }
    }
    func setDoNotDisturb(_ enabled: Bool) {
        guard canSetDoNotDisturbManually else { return }
        updateManualDoNotDisturb(enabled, until: nil)
    }
    func activateDoNotDisturb(for duration: DoNotDisturbDuration) {
        guard canSetDoNotDisturbManually else { return }
        updateManualDoNotDisturb(true, until: duration.endDate(from: currentDate()))
    }
    func expireDoNotDisturbIfNeeded(at date: Date? = nil) {
        guard manualDoNotDisturb, let end = manualDoNotDisturbUntil,
              end <= (date ?? currentDate()) else { return }
        updateManualDoNotDisturb(false, until: nil)
    }
    private func updateManualDoNotDisturb(_ enabled: Bool, until: Date?) {
        guard manualDoNotDisturb != enabled || manualDoNotDisturbUntil != until else { return }
        let wasEnabled = doNotDisturb
        manualDoNotDisturb = enabled
        manualDoNotDisturbUntil = enabled ? until : nil
        persistDoNotDisturbUntil(manualDoNotDisturbUntil)
        persistDoNotDisturb(enabled)
        scheduleDoNotDisturbExpiration()
        applyDoNotDisturbChange(wasEnabled: wasEnabled)
    }
    private func scheduleDoNotDisturbExpiration() {
        doNotDisturbExpirationTask?.cancel()
        doNotDisturbExpirationTask = nil
        guard manualDoNotDisturb, let end = manualDoNotDisturbUntil else { return }
        let delay = end.timeIntervalSince(currentDate())
        guard delay > 0 else {
            expireDoNotDisturbIfNeeded()
            return
        }
        doNotDisturbExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.expireDoNotDisturbIfNeeded()
        }
    }
    func setFocusSyncEnabled(_ enabled: Bool) {
        guard focusSyncEnabled != enabled else { return }
        let wasEnabled = doNotDisturb
        focusSyncEnabled = enabled
        persistFocusSyncEnabled(enabled)
        applyDoNotDisturbChange(wasEnabled: wasEnabled)
    }
    func setMacFocusActive(_ active: Bool) {
        guard macFocusActive != active else { return }
        let wasEnabled = doNotDisturb
        macFocusActive = active
        applyDoNotDisturbChange(wasEnabled: wasEnabled)
    }
    private func applyDoNotDisturbChange(wasEnabled: Bool) {
        if doNotDisturb && !wasEnabled {
            for index in calls.indices where calls[index].incoming && calls[index].answeredAt == nil && calls[index].phase != .ended {
                calls[index].locallyDeclined = true
                let handle = calls[index].handle
                removeIncomingNotification(handle)
                cancelIncomingAttention(handle)
                Task { try? await engine.hangup(handle, decline: true) }
            }
        }
        updateRinging()
    }

    func setPauseMediaDuringCalls(_ enabled: Bool) {
        guard pauseMediaDuringCalls != enabled else { return }
        pauseMediaDuringCalls = enabled
        persistPauseMediaDuringCalls(enabled)
        if enabled, let call = activeCalls.first(where: { $0.answeredAt != nil || !$0.incoming }) {
            pauseExternalMediaIfNeeded(for: call.handle)
        }
    }

    func setCallWaitingEnabled(_ enabled: Bool) {
        guard callWaitingEnabled != enabled else { return }
        callWaitingEnabled = enabled
        persistCallWaitingEnabled(enabled)
        guard !enabled else { return }
        for index in calls.indices where calls[index].incoming
            && calls[index].answeredAt == nil
            && calls[index].phase != .ended
            && hasEstablishedCall(excluding: calls[index].handle) {
            calls[index].locallyDeclined = true
            let handle = calls[index].handle
            removeIncomingNotification(handle)
            cancelIncomingAttention(handle)
            Task { try? await engine.hangup(handle, decline: true) }
        }
        updateRinging()
    }

    func setAutomaticallyStartListCalls(_ enabled: Bool) {
        guard automaticallyStartListCalls != enabled else { return }
        automaticallyStartListCalls = enabled
        persistAutomaticallyStartListCalls(enabled)
    }

    func setPublicCallerLookupEnabled(_ enabled: Bool) {
        guard !enabled || purchases.access.permits(.publicCallerLookup) else { return }
        guard publicCallerLookupEnabled != enabled else { return }
        publicCallerLookupEnabled = enabled
        publicCallerLookupGeneration += 1
        persistPublicCallerLookupEnabled(enabled)
        publicCallerMisses.removeAll()
        if !enabled {
            publicCallerNames.removeAll()
            resolvingPublicCallers.removeAll()
        }
    }

    func setDefaultReminderNotificationTiming(_ timing: CallReminderNotificationTiming) {
        guard defaultReminderNotificationTiming != timing else { return }
        defaultReminderNotificationTiming = timing
        persistReminderNotificationTiming(timing)
        synchronizeReminderNotifications()
    }

    func setAppleContactsEnabled(_ enabled: Bool) async {
        guard appleContactsEnabled != enabled else {
            if enabled { await refreshAppleContacts(requestAccess: true) }
            return
        }
        appleContactsEnabled = enabled
        appleContactsRefreshGeneration += 1
        persistAppleContactsEnabled(enabled)
        appleContactsError = nil
        guard enabled else {
            appleContacts.removeAll()
            appleContactsLoading = false
            return
        }
        await refreshAppleContacts(requestAccess: true)
    }

    func refreshAppleContacts(requestAccess: Bool = false) async {
        appleContactsRefreshGeneration += 1
        let generation = appleContactsRefreshGeneration
        appleContactsAuthorization = appleContactsProvider.authorizationStatus()
        if requestAccess, appleContactsAuthorization == .notDetermined {
            do {
                _ = try await appleContactsProvider.requestAccess()
                guard generation == appleContactsRefreshGeneration, appleContactsEnabled else { return }
                appleContactsAuthorization = appleContactsProvider.authorizationStatus()
            } catch {
                guard generation == appleContactsRefreshGeneration, appleContactsEnabled else { return }
                appleContactsError = L10n.error(error)
                appleContacts.removeAll()
                return
            }
        }
        guard appleContactsEnabled, appleContactsAuthorization == .authorized else {
            appleContacts.removeAll()
            return
        }
        appleContactsLoading = true
        defer {
            if generation == appleContactsRefreshGeneration { appleContactsLoading = false }
        }
        do {
            let fetched = try await appleContactsProvider.fetch()
            guard generation == appleContactsRefreshGeneration, appleContactsEnabled else { return }
            appleContacts = fetched
            appleContactsError = nil
        } catch {
            guard generation == appleContactsRefreshGeneration, appleContactsEnabled else { return }
            appleContacts.removeAll()
            appleContactsError = L10n.error(error)
        }
    }

    func openAppleContactsPrivacySettings() {
        SystemAppleContactsProvider.openPrivacySettings()
    }

    func resolvePublicCallerName(_ number: String) async {
        guard canUsePublicCallerLookup, displayContact(for: number) == nil,
              let key = PublicCallerNumbers.normalized(number),
              publicCallerNames[key] == nil, !publicCallerMisses.contains(key),
              resolvingPublicCallers.insert(key).inserted else { return }
        let generation = publicCallerLookupGeneration
        defer {
            if generation == publicCallerLookupGeneration { resolvingPublicCallers.remove(key) }
        }

        let identity = await publicCallerLookup.identity(for: key)
        guard !Task.isCancelled, canUsePublicCallerLookup,
              generation == publicCallerLookupGeneration else { return }
        guard let identity else {
            publicCallerMisses.insert(key)
            return
        }
        publicCallerNames[key] = identity.name
        for call in activeCalls where call.incoming && call.phase == .incoming
            && PublicCallerNumbers.normalized(call.remote) == key {
            postIncomingNotification(identity.name, accountName(call.accountID), call.handle)
        }
    }

    func resolvePublicCallerNames(_ numbers: [String]) async {
        var seen = Set<String>()
        for number in numbers {
            guard !Task.isCancelled else { return }
            guard seen.count < 20 else { break }
            guard let key = PublicCallerNumbers.normalized(number), seen.insert(key).inserted else { continue }
            await resolvePublicCallerName(number)
        }
    }

    func pauseExternalMediaIfNeeded(for handle: CallHandle) {
        guard pauseMediaDuringCalls, mediaPausedForCalls.insert(handle).inserted else { return }
        pauseMediaPlayback()
    }
    func receive(_ event: TelephonyEvent) {
        switch event {
        case let .registration(id, state): applyRegistrationState(state, to: id)
        case let .call(handle, accountID, remote, incoming, phase, status):
            guard !finished.contains(handle) else { return }
            let isNewCall = !calls.contains(where: { $0.handle == handle })
            if isNewCall {
                calls.append(CallSession(handle: handle, accountID: accountID, remote: remote, incoming: incoming, phase: phase))
                Task { await resolvePublicCallerName(remote) }
            }
            guard let index = calls.firstIndex(where: { $0.handle == handle }) else { return }
            calls[index].lastStatus = status
            calls[index].transition(to: phase)
            if let media = pendingMedia.removeValue(forKey: handle) {
                calls[index].held = media.0; calls[index].remoteHeld = media.1; calls[index].mediaError = media.2
            }
            let blockedByRule = Routing.isBlocked(remote, rules: snapshot.blocks, anonymous: snapshot.blockAnonymous)
            let rejectedByLineAccess = incoming && isNewCall && isAccountLockedByPro(accountID)
            let rejectedByCallWaiting = incoming && phase != .ended && !callWaitingEnabled
                && hasEstablishedCall(excluding: handle)
            if incoming && phase != .ended
                && (blockedByRule || doNotDisturb || rejectedByCallWaiting || rejectedByLineAccess) {
                if blockedByRule { calls[index].blocked = true }
                else { calls[index].locallyDeclined = true }
                removeIncomingNotification(handle)
                cancelIncomingAttention(handle)
                Task { try? await engine.hangup(handle, decline: true) }
            } else if incoming && phase == .incoming {
                postIncomingNotification(displayName(remote), accountName(accountID), handle)
                requestIncomingAttention(handle)
            } else if incoming && phase == .connected {
                removeIncomingNotification(handle)
                cancelIncomingAttention(handle)
            }
            if phase == .ended {
                let wasConnected = calls[index].answeredAt != nil
                finished.insert(handle)
                conferenceHandles.remove(handle)
                if conferenceHandles.count < 2 { conferenceHandles.removeAll() }
                mediaPausedForCalls.remove(handle)
                let record = CallRecord(session: calls[index], accountName: accountName(accountID))
                lastEndedCall = record
                var next = snapshot; next.history.insert(record, at: 0)
                do {
                    try commit(next)
                    if record.outcome == .missed {
                        unseenMissedCallIDs.insert(record.id)
                        persistUnseenMissedCallIDs(unseenMissedCallIDs)
                    }
                } catch { report(error) }
                calls.remove(at: index)
                finishReminderCall(handle, wasConnected: wasConnected)
                if incoming {
                    removeIncomingNotification(handle)
                    cancelIncomingAttention(handle)
                }
                if ready && activeCalls.isEmpty {
                    Task { await engine.releaseAudio() }
                    if networkRefreshPending { scheduleNetworkRefresh() }
                }
                if isAccountLockedByPro(accountID) {
                    Task { await reconcileLineAccess() }
                }
            }
            updateRinging()
        case let .media(handle, held, remoteHeld, error):
            if let index = calls.firstIndex(where: { $0.handle == handle }) {
                calls[index].held = held; calls[index].remoteHeld = remoteHeld; calls[index].mediaError = error
            } else if !finished.contains(handle) { pendingMedia[handle] = (held, remoteHeld, error) }
            if error != 0 { audioWarning = L10n.format("Audio connection interrupted (%lld). Check your devices.", Int64(error)) }
        case let .transfer(_, status, final):
            if final {
                information = (200..<300).contains(status)
                    ? L10n.text("Calls connected.")
                    : L10n.format("Transfer failed (SIP %lld). The calls remain available.", Int64(status))
            }
        case let .failure(code): report(EngineError(code, operation: "Telephony"))
        }
    }

    private func applyRegistrationState(_ state: RegistrationState, to id: UUID) {
        if isAccountLockedByPro(id), !activeCalls.contains(where: { $0.accountID == id }) {
            cancelPendingRegistrationState(for: id)
            registrations[id] = .disabled
            return
        }
        if state != .registered, silentlyVerifiedAccounts.contains(id) { return }
        if state == .registered || state == .disabled {
            cancelPendingRegistrationState(for: id)
        }
        if registrations[id] == .registering {
            switch state {
            case .failed, .offline:
                deferRegistrationState(state, for: id)
                return
            case .disabled, .registering, .registered:
                break
            }
        }
        if state == .registering {
            switch registrations[id] {
            case .registered, .failed, .offline, .disabled:
                return
            case .registering, nil:
                showRegistrationProgress(for: id)
                return
            }
        }
        if state == .offline, case .failed = registrations[id] { return }
        registrations[id] = state
    }

    private func showRegistrationProgress(for id: UUID) {
        cancelPendingRegistrationState(for: id)
        registrations[id] = .registering
    }

    private func deferRegistrationState(_ state: RegistrationState, for id: UUID) {
        let preservesPendingFailure = if case .failed = pendingRegistrationStates[id] {
            state == .offline
        } else {
            false
        }
        if !preservesPendingFailure {
            pendingRegistrationStates[id] = state
        }
        guard pendingRegistrationTasks[id] == nil else { return }
        pendingRegistrationTasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if networkRefreshInProgress || networkRefreshRequestedDuringRun || networkRefreshDebounceTask != nil {
                    continue
                }
                pendingRegistrationTasks[id] = nil
                guard registrations[id] == .registering else {
                    pendingRegistrationStates.removeValue(forKey: id)
                    return
                }
                guard let state = pendingRegistrationStates.removeValue(forKey: id) else { return }
                registrations[id] = state
                return
            }
        }
    }

    func cancelPendingRegistrationState(for id: UUID) {
        pendingRegistrationTasks.removeValue(forKey: id)?.cancel()
        pendingRegistrationStates.removeValue(forKey: id)
    }
    func commit(_ value: AppSnapshot) throws {
        guard let repository, storageError == nil else { throw AppError.storageUnavailable }
        try repository.save(value); snapshot = value
    }
    var missedCallBadgeCount: Int {
        snapshot.history.count { $0.outcome == .missed && unseenMissedCallIDs.contains($0.id) }
    }
    func markMissedCallsSeen() {
        guard !unseenMissedCallIDs.isEmpty else { return }
        unseenMissedCallIDs.removeAll()
        persistUnseenMissedCallIDs(unseenMissedCallIDs)
    }
    func removeMissedCallBadges(for ids: Set<UUID>) {
        let previousCount = unseenMissedCallIDs.count
        unseenMissedCallIDs.subtract(ids)
        if unseenMissedCallIDs.count != previousCount {
            persistUnseenMissedCallIDs(unseenMissedCallIDs)
        }
    }
    func accountName(_ id: UUID) -> String { snapshot.accounts.first { $0.id == id }?.name ?? L10n.text("Removed Line") }
    func displayName(_ number: String) -> String {
        if let contact = contact(for: number) { return contact.name }
        if let contact = appleContact(for: number) { return contact.name }
        if canUsePublicCallerLookup, let key = PublicCallerNumbers.normalized(number),
           let publicName = publicCallerNames[key] { return publicName }
        return ["unknown", "anonymous", "unavailable", "restricted"].contains(number.lowercased()) ? L10n.text("Unknown") : number
    }
    func contact(for number: String) -> PhoneContact? {
        guard let key = try? CallDestination(number).matchingKey() else { return nil }
        return snapshot.contacts.first { $0.numbers.contains { (try? CallDestination($0).matchingKey()) == key } }
    }
    func appleContact(for number: String) -> AppleContact? {
        guard appleContactsEnabled, let key = try? CallDestination(number).matchingKey() else { return nil }
        return appleContacts.first { contact in
            contact.numbers.contains { (try? CallDestination($0).matchingKey()) == key }
        }
    }
    func displayContact(for number: String) -> PhoneContact? {
        contact(for: number) ?? appleContact(for: number)?.presentationContact
    }

    private static func removingAppleDuplicates(_ apple: [AppleContact], local: [PhoneContact]) -> [AppleContact] {
        let localNumbers = Set(local.flatMap(\.numbers).compactMap { try? CallDestination($0).matchingKey() })
        return apple.compactMap { contact in
            let uniqueNumbers = contact.phoneNumbers.filter { phoneNumber in
                let number = phoneNumber.value
                guard let key = try? CallDestination(number).matchingKey() else { return false }
                return !localNumbers.contains(key)
            }
            guard !uniqueNumbers.isEmpty else { return nil }
            return AppleContact(id: contact.id, name: contact.name, company: contact.company,
                                phoneNumbers: uniqueNumbers, photoData: contact.photoData)
        }
    }
    @discardableResult func prepareDial(_ value: String, accountID: UUID? = nil) -> Bool {
        preparedReminderID = nil
        do {
            dialText = try CallDestination(value).value
            if let accountID, !isAccountLockedByPro(accountID) { selectedAccountID = accountID }
            return true
        } catch {
            report(error)
            return false
        }
    }
    func report(_ error: Error) {
        logger.error("Operation failed; engine code: \((error as? EngineError)?.code ?? -1, privacy: .public)")
        errorMessage = L10n.error(error)
    }
    func clearIncomingAlert(_ handle: CallHandle) {
        removeIncomingNotification(handle)
        cancelIncomingAttention(handle)
    }
    func markIncomingDeclined(_ handle: CallHandle) {
        if let index = calls.firstIndex(where: { $0.handle == handle }) { calls[index].locallyDeclined = true }
        clearIncomingAlert(handle)
        updateRinging()
    }
    func reconcileProPresentation() {
        publicCallerLookupGeneration += 1
        resolvingPublicCallers.removeAll()
        if !purchases.access.permits(.publicCallerLookup) {
            publicCallerNames.removeAll()
            publicCallerMisses.removeAll()
        }
        updateRinging()
    }

    private func updateRinging() {
        let audibleCalls = doNotDisturb ? [] : activeCalls.filter { !$0.locallyDeclined }
        let accounts = snapshot.accounts.map { account in
            var effective = account
            effective.ringtone = effectiveRingtone(account.ringtone)
            return effective
        }
        ringer.update(calls: audibleCalls, accounts: accounts)
    }

    private func hasEstablishedCall(excluding handle: CallHandle) -> Bool {
        calls.contains {
            $0.handle != handle && $0.phase != .ended && ($0.answeredAt != nil || !$0.incoming)
        }
    }
}
