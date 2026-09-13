import Foundation
import Synchronization
import Testing
import TelefonDomain
import TelefonData
@testable import TelefonX

@Suite @MainActor struct PhoneModelTests {
    @Test(arguments: [false, true])
    func deletingALineOnlyRemovesItsHistoryWhenRequested(includingHistory: Bool) async throws {
        let deleted = PhoneAccount(name: "Deleted", username: "deleted", domain: "sip.example.com", sortIndex: 0)
        let retained = PhoneAccount(name: "Retained", username: "retained", domain: "sip.example.com", sortIndex: 1)
        let deletedCall = CallRecord(
            session: CallSession(handle: .init(slot: 1, generation: 1), accountID: deleted.id,
                                 remote: "101", incoming: false, phase: .ended),
            accountName: deleted.name
        )
        let retainedCall = CallRecord(
            session: CallSession(handle: .init(slot: 2, generation: 1), accountID: retained.id,
                                 remote: "102", incoming: true, phase: .ended),
            accountName: retained.name
        )
        let contact = PhoneContact(name: "Ada", numbers: ["101"], preferredAccountID: deleted.id)
        let repository = MemoryRepository()
        repository.value.accounts = [deleted, retained]
        repository.value.defaultAccountID = deleted.id
        repository.value.contacts = [contact]
        repository.value.history = [deletedCall, retainedCall]
        let model = PhoneModel(engine: TestEngine(), credentials: PasswordCredentials(), repository: repository,
                               purchases: testProPurchases())

        try await model.deleteAccount(deleted.id, includingHistory: includingHistory)

        #expect(model.snapshot.accounts.map(\.id) == [retained.id])
        #expect(model.snapshot.accounts.first?.sortIndex == 0)
        #expect(model.snapshot.defaultAccountID == retained.id)
        #expect(model.snapshot.contacts.first?.id == contact.id)
        #expect(model.snapshot.contacts.first?.preferredAccountID == nil)
        #expect(model.snapshot.history.contains(where: { $0.id == retainedCall.id }))
        #expect(model.snapshot.history.contains(where: { $0.id == deletedCall.id }) == !includingHistory)
        #expect(repository.saveCount == 1)
    }

    @Test func expiredProKeepsExtraLinesButLocksAndUnregistersThem() async throws {
        let first = PhoneAccount(name: "First", username: "first", domain: "sip.example.com", sortIndex: 0)
        let second = PhoneAccount(name: "Second", username: "second", domain: "sip.example.com", sortIndex: 1)
        let third = PhoneAccount(name: "Third", username: "third", domain: "sip.example.com", sortIndex: 2)
        let repository = MemoryRepository()
        repository.value.accounts = [first, second, third]
        repository.value.defaultAccountID = third.id
        repository.value.contacts = [PhoneContact(name: "Ada", numbers: ["101"], preferredAccountID: second.id)]
        repository.value.dialRules = [DialRule(prefix: "0173", accountID: third.id)]
        let priorCall = CallSession(handle: .init(slot: 40, generation: 1), accountID: second.id,
                                    remote: "101", incoming: false, phase: .ended)
        repository.value.history = [CallRecord(session: priorCall, accountName: second.name)]
        let storedSnapshot = repository.value
        let engine = TestEngine(acceptRegistrations: true)
        let model = PhoneModel(
            engine: engine,
            credentials: PasswordCredentials(),
            repository: repository,
            purchases: PurchaseStore(internalEvaluation: false, productIDs: [])
        )
        model.ready = true
        model.registrations = [first.id: .registered, second.id: .registered, third.id: .registered]

        await model.applyProAccessChange()

        #expect(model.snapshot == storedSnapshot)
        #expect(model.snapshot.history.first?.accountID == second.id)
        #expect(model.snapshot.history.first?.accountName == second.name)
        #expect(model.snapshot.contacts.first?.preferredAccountID == second.id)
        #expect(model.snapshot.dialRules.first?.accountID == third.id)
        #expect(model.snapshot.defaultAccountID == third.id)
        #expect(repository.saveCount == 0)
        #expect(model.selectedAccountID == first.id)
        #expect(!model.isAccountLockedByPro(first.id))
        #expect(model.isAccountLockedByPro(second.id))
        #expect(model.isAccountLockedByPro(third.id))
        #expect(model.registrations[first.id] == .registered)
        #expect(model.registrations[second.id] == .disabled)
        #expect(model.registrations[third.id] == .disabled)
        #expect(Set(await engine.unregisteredAccounts) == [second.id, third.id])
        await #expect(throws: ProAccessError.self) {
            try await model.saveAccount(second, password: "secret")
        }
    }

    @Test func aHistoricalCallOnALockedLineFallsBackToTheFreeLine() async throws {
        let first = PhoneAccount(name: "First", username: "first", domain: "sip.example.com", sortIndex: 0)
        let second = PhoneAccount(name: "Second", username: "second", domain: "sip.example.com", sortIndex: 1)
        let repository = MemoryRepository()
        repository.value.accounts = [first, second]
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: repository,
            authorizeMicrophone: { true },
            purchases: PurchaseStore(internalEvaluation: false, productIDs: [])
        )
        model.ready = true
        model.selectedAccountID = first.id
        model.registrations = [first.id: .registered, second.id: .disabled]

        #expect(model.canCall("101", preferredAccountID: second.id))
        #expect(await model.callNumber("101", preferredAccountID: second.id) != nil)
        #expect(await engine.lastDestination == "101")
        #expect(await engine.lastAccountID == first.id)
    }

    @Test func restoredProReactivatesStoredLinesAndTheirDefaultSelection() async {
        let first = PhoneAccount(name: "First", username: "first", domain: "sip.example.com", sortIndex: 0)
        let second = PhoneAccount(name: "Second", username: "second", domain: "sip.example.com", sortIndex: 1)
        let repository = MemoryRepository()
        repository.value.accounts = [first, second]
        repository.value.defaultAccountID = second.id
        repository.value.contacts = [PhoneContact(name: "Ada", numbers: ["101"], preferredAccountID: second.id)]
        repository.value.dialRules = [DialRule(prefix: "0173", accountID: second.id)]
        let storedSnapshot = repository.value
        let engine = TestEngine(acceptRegistrations: true)
        let model = PhoneModel(
            engine: engine,
            credentials: PasswordCredentials(),
            repository: repository,
            purchases: PurchaseStore(internalEvaluation: true, productIDs: [])
        )
        model.ready = true
        model.registrations = [first.id: .disabled, second.id: .disabled]

        await model.applyProAccessChange()

        #expect(model.snapshot == storedSnapshot)
        #expect(repository.saveCount == 0)
        #expect(model.selectedAccountID == second.id)
        #expect(Set(await engine.registeredAccounts) == [first.id, second.id])
    }

    @Test func expiredProLetsAnActiveExtraLineFinishBeforeUnregisteringIt() async {
        let first = PhoneAccount(name: "First", username: "first", domain: "sip.example.com", sortIndex: 0)
        let second = PhoneAccount(name: "Second", username: "second", domain: "sip.example.com", sortIndex: 1)
        let repository = MemoryRepository()
        repository.value.accounts = [first, second]
        let engine = TestEngine(acceptRegistrations: true)
        let model = PhoneModel(
            engine: engine,
            credentials: PasswordCredentials(),
            repository: repository,
            purchases: PurchaseStore(internalEvaluation: false, productIDs: [])
        )
        let handle = CallHandle(slot: 41, generation: 1)
        model.ready = true
        model.registrations = [first.id: .registered, second.id: .registered]
        model.calls = [CallSession(handle: handle, accountID: second.id, remote: "101",
                                   incoming: false, phase: .connected)]

        await model.applyProAccessChange()
        #expect(await engine.unregisteredAccounts.isEmpty)
        #expect(model.calls.count == 1)

        model.receive(.call(handle, accountID: second.id, remote: "101",
                            incoming: false, phase: .ended, status: 200))
        let didUnregister = await waitUntil {
            await engine.unregisteredAccounts.contains(second.id)
        }
        #expect(didUnregister)
        #expect(model.snapshot.accounts == [first, second])
        #expect(model.registrations[second.id] == .disabled)
    }

    @Test func expiredProRejectsANewIncomingCallOnALockedLine() async {
        let first = PhoneAccount(name: "First", username: "first", domain: "sip.example.com", sortIndex: 0)
        let second = PhoneAccount(name: "Second", username: "second", domain: "sip.example.com", sortIndex: 1)
        let repository = MemoryRepository()
        repository.value.accounts = [first, second]
        let engine = TestEngine(acceptDeclines: true)
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: repository,
            purchases: PurchaseStore(internalEvaluation: false, productIDs: [])
        )
        let handle = CallHandle(slot: 42, generation: 1)

        model.receive(.call(handle, accountID: second.id, remote: "101",
                            incoming: true, phase: .incoming, status: 180))
        let didDecline = await waitUntil {
            await engine.declinedCalls.contains(handle)
        }

        #expect(didDecline)
        #expect(model.calls.first(where: { $0.handle == handle })?.locallyDeclined == true)
    }

    @Test func freeRemindersRemainExportableButCannotBeUsedOrChanged() async throws {
        let repository = MemoryRepository()
        let reminder = CallReminder(name: "Ada", number: "101", note: "Angebot", dueAt: Date().addingTimeInterval(3600))
        repository.value.reminders = [reminder]
        let removed = Mutex<Set<UUID>>([])
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository,
                               removeReminderNotification: { id in removed.withLock { _ = $0.insert(id) } },
                               purchases: PurchaseStore(internalEvaluation: false, productIDs: []))
        #expect(throws: ProAccessError.self) { try model.saveReminder(reminder) }
        #expect(throws: ProAccessError.self) { try model.completeReminder(reminder.id) }
        #expect(throws: ProAccessError.self) { try model.snoozeReminder(reminder.id) }
        #expect(throws: ProAccessError.self) { try model.deleteReminders([reminder.id]) }
        #expect(throws: ProAccessError.self) { try model.completeReminders([reminder.id]) }
        let originalDial = model.dialText
        model.prepareReminderCall(reminder.id)
        await model.performReminderListAction(reminder.id)
        await model.callReminderNow(reminder.id)
        await model.applyProAccessChange()
        #expect(model.dialText == originalDial)
        #expect(model.pendingReminders.isEmpty)
        #expect(!model.canCallReminder(reminder))
        #expect(model.snapshot.reminders == [reminder])
        #expect(repository.saveCount == 0)
        #expect(removed.withLock { $0.contains(reminder.id) })
        let csv = RemindersCSV.encode(model.snapshot.reminders)
        #expect(csv.contains("\"Ada\",\"101\","))
        #expect(csv.contains("\"Angebot\",\"Offen\","))
    }

    @Test(arguments: [false, true]) func customRingtoneAccessPreservesTheStoredChoice(pro: Bool) {
        let asset = AudioAsset(name: "Eigener Ton")
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository(),
                               purchases: PurchaseStore(internalEvaluation: pro, productIDs: []))
        let choice = LineRingtone.file(asset)
        #expect(model.effectiveRingtone(choice) == (pro ? choice : .system(.glass)))
        #expect(model.effectiveRingtone(.system(.basso)) == .system(.basso))
        #expect(choice == .file(asset))
    }

    @Test func freePublicLookupDoesNotSendRequestsButLocalNamesRemainAvailable() async {
        let lookup = TestPublicCallerLookup(identity: nil)
        let repository = MemoryRepository()
        repository.value.contacts = [PhoneContact(name: "Ada", numbers: ["101"])]
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository,
                               publicCallerLookup: lookup, initialPublicCallerLookupEnabled: true,
                               purchases: PurchaseStore(internalEvaluation: false, productIDs: []))
        await model.resolvePublicCallerName("+49374574447100")
        #expect(await lookup.requests.isEmpty)
        #expect(!model.canUsePublicCallerLookup)
        #expect(model.displayName("101") == "Ada")
    }

    @Test func freeHoldMusicCannotBeInstalledAndStoredAssetIsRetained() async {
        let repository = MemoryRepository()
        let asset = AudioAsset(name: "Wartemusik")
        repository.value.holdMusic = asset
        let engine = TestEngine()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository,
                               purchases: PurchaseStore(internalEvaluation: false, productIDs: []))
        await #expect(throws: ProAccessError.self) { try await model.saveHoldMusic(asset) }
        await model.restoreHoldMusic()
        #expect(await engine.configuredMusic == nil)
        #expect(model.snapshot.holdMusic == asset)
        #expect(repository.saveCount == 0)
    }

    @Test(arguments: [false, true]) func bulkReminderActionsCommitOnceAndPreserveUnselected(delete: Bool) throws {
        let repository = MemoryRepository()
        let first = CallReminder(name: "First", number: "101", dueAt: Date())
        var completed = CallReminder(name: "Done", number: "102", dueAt: Date())
        completed.completedAt = Date(timeIntervalSince1970: 100)
        let other = CallReminder(name: "Other", number: "103", dueAt: Date())
        repository.value.reminders = [first, completed, other]
        let cancelled = Mutex<Set<UUID>>([])
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository,
                               removeReminderNotification: { id in cancelled.withLock { _ = $0.insert(id) } },
                               purchases: testProPurchases())
        let ids: Set<UUID> = [first.id, completed.id, UUID()]
        repository.failSave = true
        #expect(throws: TestFailure.self) {
            if delete { try model.deleteReminders(ids) } else { try model.completeReminders(ids) }
        }
        #expect(model.snapshot.reminders == [first, completed, other])
        #expect(cancelled.withLock { $0.isEmpty })
        repository.failSave = false
        if delete { try model.deleteReminders(ids) } else { try model.completeReminders(ids) }
        #expect(repository.saveCount == 1)
        #expect(model.snapshot.reminders.last == other)
        if delete {
            #expect(model.snapshot.reminders == [other])
            #expect(cancelled.withLock { $0 } == [first.id, completed.id])
        } else {
            #expect(model.snapshot.reminders[0].completedAt != nil)
            #expect(model.snapshot.reminders[1] == completed)
            #expect(cancelled.withLock { $0 } == [first.id])
        }
    }

    @Test func dockBadgeTracksOnlyUnseenMissedCalls() throws {
        var persistedIDs = Set<UUID>()
        let model = PhoneModel(
            engine: TestEngine(),
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            persistUnseenMissedCallIDs: { persistedIDs = $0 }
        )
        let handle = CallHandle(slot: 4, generation: 1)
        let accountID = UUID()

        model.receive(.call(handle, accountID: accountID, remote: "101", incoming: true, phase: .ended, status: 487))

        let missedCall = try #require(model.snapshot.history.first)
        #expect(missedCall.outcome == .missed)
        #expect(model.missedCallBadgeCount == 1)
        #expect(persistedIDs == [missedCall.id])

        model.markMissedCallsSeen()
        #expect(model.missedCallBadgeCount == 0)
        #expect(persistedIDs.isEmpty)
    }

    @Test func deletingAnUnseenMissedCallAlsoRemovesItsBadgeState() throws {
        let handle = CallHandle(slot: 5, generation: 1)
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository())
        model.receive(.call(handle, accountID: UUID(), remote: "102", incoming: true, phase: .ended, status: 487))
        let missedCall = try #require(model.snapshot.history.first)

        try model.deleteHistoryRecords([missedCall.id])

        #expect(model.missedCallBadgeCount == 0)
        #expect(model.unseenMissedCallIDs.isEmpty)
    }

    @Test func shutdownDrainsTerminalEventsAndWritesHistoryOnce() async throws {
        let account = UUID(), handle = CallHandle(slot: 0, generation: 1)
        let terminal = TelephonyEvent.call(handle, accountID: account, remote: "123", incoming: false, phase: .ended, status: 200)
        let engine = TestEngine(stopEvents: [terminal, terminal])
        let repository = MemoryRepository()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository)
        await model.start()
        model.receive(.call(handle, accountID: account, remote: "123", incoming: false, phase: .calling, status: 0))
        model.receive(.call(handle, accountID: account, remote: "123", incoming: false, phase: .connected, status: 200))

        await model.shutdown()

        #expect(!model.ready)
        #expect(model.activeCalls.isEmpty)
        #expect(repository.saveCount == 1)
        let record = try #require(repository.value.history.first)
        #expect(record.outcome == .answered)
        #expect(record.remote == "123")
        #expect(model.snapshot.history == repository.value.history)
        // A delayed callback cannot resurrect a completed generation.
        model.receive(.call(handle, accountID: account, remote: "123", incoming: false, phase: .connected, status: 200))
        #expect(model.calls.isEmpty)
    }

    @Test func finalEndedCallReleasesAudioExactlyOnce() async {
        let engine = TestEngine()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository())
        let account = UUID()
        let first = CallHandle(slot: 1, generation: 1), second = CallHandle(slot: 2, generation: 1)
        model.ready = true
        model.receive(.call(first, accountID: account, remote: "101", incoming: false, phase: .connected, status: 200))
        model.receive(.call(second, accountID: account, remote: "102", incoming: false, phase: .connected, status: 200))

        model.receive(.call(first, accountID: account, remote: "101", incoming: false, phase: .ended, status: 200))
        for _ in 0..<10 { await Task.yield() }
        #expect(await engine.releaseCount == 0)

        model.receive(.call(second, accountID: account, remote: "102", incoming: false, phase: .ended, status: 200))
        for _ in 0..<20 where await engine.releaseCount == 0 { await Task.yield() }
        #expect(await engine.releaseCount == 1)
    }

    @Test func hangupRemovesCallThatNativeEngineAlreadyEnded() async throws {
        let engine = TestEngine(hangupError: EngineError(EngineError.invalidOperationCode, operation: "Hang Up"))
        let repository = MemoryRepository()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository)
        let account = UUID(), handle = CallHandle(slot: 3, generation: 1)
        model.receive(.call(handle, accountID: account, remote: "101", incoming: false, phase: .connected, status: 200))

        await model.hangup(try #require(model.activeCalls.first))

        #expect(model.activeCalls.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(repository.value.history.first?.remote == "101")
        #expect(repository.value.history.first?.outcome == .answered)
    }

    @Test func unreadableStorageNeverStartsEngineOrOverwritesData() async {
        let engine = TestEngine(), repository = MemoryRepository(failLoad: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository)
        await model.start()
        #expect(model.storageError != nil)
        #expect(!model.ready)
        #expect(await engine.startCount == 0)
        #expect(repository.saveCount == 0)
        #expect(throws: AppError.self) { try model.commit(AppSnapshot()) }
        #expect(repository.saveCount == 0)
    }

    @Test func configurationTransactionPreventsNewOutgoingCalls() async {
        let engine = TestEngine()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository())
        await model.start()
        model.configurationBusy = true
        model.dialText = "123"
        await model.dial()
        #expect(!model.canDial)
        #expect(await engine.callCount == 0)
        #expect(model.dialText == "123")
        await model.shutdown()
    }

    @Test func registrationFailureStaysInlineInsteadOfShowingAModalAlert() async {
        let engine = TestEngine()
        let model = PhoneModel(
            engine: engine,
            credentials: PasswordCredentials(),
            repository: MemoryRepository()
        )
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        model.ready = true

        await model.register(account)

        #expect(model.registrations[account.id] == .failed(-1))
        #expect(model.errorMessage == nil)
    }

    @Test func automaticRegistrationRetriesKeepAStableUnavailablePresentation() {
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository())
        let accountID = UUID()
        model.registrations[accountID] = .failed(503)

        model.receive(.registration(accountID, .registering))
        #expect(model.registrations[accountID] == .failed(503))

        model.receive(.registration(accountID, .offline))
        #expect(model.registrations[accountID] == .failed(503))

        model.receive(.registration(accountID, .registered))
        #expect(model.registrations[accountID] == .registered)

        model.receive(.registration(accountID, .registering))
        #expect(model.registrations[accountID] == .registered)
    }

    @Test func connectingLineStaysYellowAcrossAnImmediateRetryBeforeTurningGreen() async throws {
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository())
        let accountID = UUID()
        model.registrations[accountID] = .registering

        model.receive(.registration(accountID, .failed(503)))
        #expect(model.registrations[accountID] == .registering)

        try await Task.sleep(for: .milliseconds(300))
        model.receive(.registration(accountID, .registering))
        try await Task.sleep(for: .milliseconds(800))
        #expect(model.registrations[accountID] == .registering)

        model.receive(.registration(accountID, .registered))
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(model.registrations[accountID] == .registered)
    }

    @Test func connectingLineTurnsRedAfterItsFinalFailureSettles() async throws {
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository())
        let accountID = UUID()
        model.registrations[accountID] = .registering

        model.receive(.registration(accountID, .failed(503)))
        #expect(model.registrations[accountID] == .registering)

        let didSettle = await waitUntil {
            model.registrations[accountID] == .failed(503)
        }
        #expect(didSettle)
        #expect(model.registrations[accountID] == .failed(503))
    }

    @Test func reconnectRebuildsOnlyTheRequestedRegistration() async throws {
        let engine = TestEngine(acceptRegistrations: true)
        let repository = MemoryRepository()
        let first = PhoneAccount(name: "VPN", username: "vpn", domain: "sip.vpn.example")
        let second = PhoneAccount(name: "Office", username: "office", domain: "sip.office.example")
        repository.value.accounts = [first, second]
        let model = PhoneModel(engine: engine, credentials: PasswordCredentials(), repository: repository,
                               purchases: testProPurchases())
        model.ready = true
        model.registrations[first.id] = .failed(503)
        model.registrations[second.id] = .registered

        await model.reconnect(accountID: first.id)

        #expect(await engine.unregisteredAccounts == [first.id])
        #expect(await engine.registeredAccounts == [first.id])
        #expect(model.registrations[first.id] == .registering)
        #expect(model.registrations[second.id] == .registered)
        #expect(!model.configurationBusy)
    }

    @Test func networkChangeRefreshesFailedRegistrationButKeepsHealthyLine() async {
        let engine = TestEngine(acceptRegistrations: true)
        let repository = MemoryRepository()
        let vpn = PhoneAccount(name: "VPN", username: "vpn", domain: "sip.vpn.example")
        let healthy = PhoneAccount(name: "Office", username: "office", domain: "sip.office.example")
        repository.value.accounts = [vpn, healthy]
        let model = PhoneModel(engine: engine, credentials: PasswordCredentials(), repository: repository,
                               purchases: testProPurchases())
        model.ready = true
        model.registrations[vpn.id] = .failed(503)
        model.registrations[healthy.id] = .registered

        await model.networkDidChange()

        #expect(await engine.networkChangeCount == 1)
        #expect(await engine.unregisteredAccounts == [vpn.id])
        #expect(await engine.registeredAccounts == [vpn.id])
        #expect(model.registrations[healthy.id] == .registered)
        #expect(await engine.registrationVerificationCount == 1)
    }

    @Test func registeredLineHealthCheckDetectsAStaleVPNRegistration() async {
        let engine = TestEngine(registrationAvailable: false)
        let repository = MemoryRepository()
        let account = PhoneAccount(name: "VPN", username: "vpn", domain: "sip.vpn.example")
        repository.value.accounts = [account]
        let model = PhoneModel(engine: engine, credentials: PasswordCredentials(), repository: repository,
                               purchases: testProPurchases())
        model.ready = true
        model.registrations[account.id] = .registered

        await model.verifyRegisteredAccounts()

        #expect(model.registrations[account.id] == .failed(408))
        #expect(await engine.registrationVerificationCount == 1)
    }

    @Test func registeredLinesAreVerifiedInParallelWithoutIntermediateStatusChanges() async {
        let engine = TestEngine(registrationVerificationDelay: .milliseconds(50))
        let repository = MemoryRepository()
        let accounts = (0..<3).map {
            PhoneAccount(name: "Line \($0)", username: "line\($0)", domain: "sip.example.com")
        }
        repository.value.accounts = accounts
        let model = PhoneModel(engine: engine, credentials: PasswordCredentials(), repository: repository,
                               purchases: testProPurchases())
        model.ready = true
        model.registrations = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, .registered) })

        await model.verifyRegisteredAccounts()

        #expect(await engine.registrationVerificationCount == 3)
        #expect(await engine.maximumConcurrentRegistrationVerifications == 3)
        #expect(accounts.allSatisfy { model.registrations[$0.id] == .registered })
    }

    @Test func networkRefreshDebouncesBurstsAndQueuesOneFollowUpRun() async throws {
        let engine = TestEngine()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository())
        model.ready = true

        model.scheduleNetworkRefresh()
        model.scheduleNetworkRefresh()
        model.scheduleNetworkRefresh()
        let initialRefreshStarted = await waitUntil {
            await engine.networkChangeCount == 1
        }
        #expect(initialRefreshStarted)
        #expect(await engine.networkChangeCount == 1)

        await model.networkDidChange()
        let followUpRefreshStarted = await waitUntil {
            await engine.networkChangeCount == 2
        }
        #expect(followUpRefreshStarted)
        #expect(await engine.networkChangeCount == 2)
        await model.shutdown()
    }

    @Test func doNotDisturbDeclinesIncomingButKeepsLinesAndOutgoingCallingAvailable() async throws {
        let engine = TestEngine(acceptCalls: true, acceptDeclines: true)
        var persisted: [Bool] = []
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(),
                               authorizeMicrophone: { true }, persistDoNotDisturb: { persisted.append($0) })
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        model.snapshot.accounts = [account]
        model.selectedAccountID = account.id
        model.ready = true
        model.registrations[account.id] = .registered

        model.setDoNotDisturb(true)
        #expect(model.doNotDisturb && persisted == [true])
        #expect(model.snapshot.accounts[0].enabled)
        #expect(model.registrations[account.id] == .registered)

        let handle = CallHandle(slot: 7, generation: 1)
        model.receive(.call(handle, accountID: account.id, remote: "101", incoming: true, phase: .incoming, status: 180))
        for _ in 0..<10 where await engine.declinedCalls.isEmpty { await Task.yield() }
        #expect(await engine.declinedCalls == [handle])
        #expect(model.calls.first?.locallyDeclined == true)
        #expect(model.calls.first?.blocked == false)
        #expect(model.presentedCalls.isEmpty)

        model.receive(.call(handle, accountID: account.id, remote: "101", incoming: true, phase: .ended, status: 486))
        #expect(model.snapshot.history.first?.outcome == .declined)

        model.setDoNotDisturb(false)
        model.dialText = "102"
        #expect(model.canDial)
        #expect(persisted == [true, false])
    }

    @Test func macFocusSyncControlsDoNotDisturbWithoutOverwritingManualPreference() {
        var persistedSyncValues: [Bool] = []
        var persistedManualValues: [Bool] = []
        let model = PhoneModel(
            engine: TestEngine(),
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            initialDoNotDisturb: true,
            persistDoNotDisturb: { persistedManualValues.append($0) },
            persistFocusSyncEnabled: { persistedSyncValues.append($0) }
        )

        #expect(model.doNotDisturb)
        model.setFocusSyncEnabled(true)
        #expect(!model.doNotDisturb)
        #expect(!model.canSetDoNotDisturbManually)
        model.setDoNotDisturb(true)
        #expect(persistedManualValues.isEmpty)

        model.setMacFocusActive(true)
        #expect(model.doNotDisturb)
        model.setMacFocusActive(false)
        #expect(!model.doNotDisturb)

        model.setFocusSyncEnabled(false)
        #expect(model.doNotDisturb)
        #expect(model.canSetDoNotDisturbManually)
        #expect(persistedSyncValues == [true, false])
    }

    @Test func timedDoNotDisturbPersistsItsEndAndExpires() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expectedEnd = now.addingTimeInterval(30 * 60)
        var persistedValues: [Bool] = []
        var persistedEnds: [Date?] = []
        let model = PhoneModel(
            engine: TestEngine(),
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            persistDoNotDisturb: { persistedValues.append($0) },
            persistDoNotDisturbUntil: { persistedEnds.append($0) },
            currentDate: { now }
        )

        model.activateDoNotDisturb(for: .thirtyMinutes)

        #expect(model.doNotDisturb)
        #expect(model.manualDoNotDisturbUntil == expectedEnd)
        #expect(persistedValues == [true])
        #expect(try #require(persistedEnds.first) == expectedEnd)

        model.expireDoNotDisturbIfNeeded(at: expectedEnd.addingTimeInterval(-1))
        #expect(model.doNotDisturb)

        model.expireDoNotDisturbIfNeeded(at: expectedEnd)
        #expect(!model.doNotDisturb)
        #expect(model.manualDoNotDisturbUntil == nil)
        #expect(persistedValues == [true, false])
        #expect(persistedEnds.count == 2)
        #expect(persistedEnds[1] == nil)
    }

    @Test func everyTimedDoNotDisturbDurationEndsAtItsExactBoundary() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cases: [(DoNotDisturbDuration, TimeInterval)] = [
            (.thirtyMinutes, 30 * 60),
            (.oneHour, 60 * 60),
            (.twoHours, 2 * 60 * 60)
        ]

        for (duration, interval) in cases {
            let model = PhoneModel(
                engine: TestEngine(),
                credentials: EmptyCredentials(),
                repository: MemoryRepository(),
                currentDate: { now }
            )
            let expectedEnd = now.addingTimeInterval(interval)

            model.activateDoNotDisturb(for: duration)
            #expect(model.manualDoNotDisturbUntil == expectedEnd)

            model.expireDoNotDisturbIfNeeded(at: expectedEnd.addingTimeInterval(-0.001))
            #expect(model.doNotDisturb)

            model.expireDoNotDisturbIfNeeded(at: expectedEnd)
            #expect(!model.doNotDisturb)
        }
    }

    @Test func doNotDisturbUntilDisabledNeverCreatesAnAutomaticDeadline() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let model = PhoneModel(
            engine: TestEngine(),
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            currentDate: { now }
        )

        model.activateDoNotDisturb(for: .untilDisabled)
        model.expireDoNotDisturbIfNeeded(at: now.addingTimeInterval(365 * 24 * 60 * 60))

        #expect(model.manualDoNotDisturb)
        #expect(model.manualDoNotDisturbUntil == nil)
        #expect(model.doNotDisturb)
    }

    @Test func expiredTimedPreferenceDoesNotReturnAfterFocusSyncEnds() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let model = PhoneModel(
            engine: TestEngine(),
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            currentDate: { now }
        )

        model.activateDoNotDisturb(for: .oneHour)
        model.setFocusSyncEnabled(true)
        model.expireDoNotDisturbIfNeeded(at: now.addingTimeInterval(60 * 60))
        model.setFocusSyncEnabled(false)

        #expect(!model.manualDoNotDisturb)
        #expect(model.manualDoNotDisturbUntil == nil)
        #expect(!model.doNotDisturb)
    }

    @Test func expiredPersistedDoNotDisturbIsDisabledOnInitialization() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let model = PhoneModel(
            engine: TestEngine(),
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            initialDoNotDisturb: true,
            initialDoNotDisturbUntil: now.addingTimeInterval(-1),
            currentDate: { now }
        )

        #expect(!model.manualDoNotDisturb)
        #expect(model.manualDoNotDisturbUntil == nil)
        #expect(!model.doNotDisturb)
    }

    @Test func incomingCallRequestsAttentionAndExplicitDeclineClearsIt() async throws {
        let engine = TestEngine(acceptDeclines: true)
        var notifications: [CallHandle] = []
        var removedNotifications: [CallHandle] = []
        var attentionRequests: [CallHandle] = []
        var cancelledAttention: [CallHandle] = []
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            postIncomingNotification: { _, _, handle in notifications.append(handle) },
            removeIncomingNotification: { removedNotifications.append($0) },
            requestIncomingAttention: { attentionRequests.append($0) },
            cancelIncomingAttention: { cancelledAttention.append($0) }
        )
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        model.snapshot.accounts = [account]
        let handle = CallHandle(slot: 8, generation: 1)

        model.receive(.call(handle, accountID: account.id, remote: "101", incoming: true, phase: .incoming, status: 180))

        #expect(notifications == [handle])
        #expect(attentionRequests == [handle])
        let call = try #require(model.calls.first)
        await model.hangup(call)

        #expect(await engine.declinedCalls == [handle])
        #expect(model.calls.first?.locallyDeclined == true)
        #expect(removedNotifications == [handle])
        #expect(cancelledAttention == [handle])
    }

    @Test func disabledCallWaitingRejectsOnlyASecondIncomingCall() async {
        let engine = TestEngine(acceptDeclines: true)
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            initialCallWaitingEnabled: false
        )
        let account = PhoneAccount()
        let idleIncoming = CallHandle(slot: 1, generation: 1)
        model.snapshot.accounts = [account]

        model.receive(.call(idleIncoming, accountID: account.id, remote: "101", incoming: true, phase: .incoming, status: 180))
        await Task.yield()
        #expect(await engine.declinedCalls.isEmpty)

        var established = CallSession(
            handle: CallHandle(slot: 2, generation: 1),
            accountID: account.id,
            remote: "102",
            incoming: false,
            phase: .connected
        )
        established.answeredAt = established.startedAt
        model.calls = [established]
        let waiting = CallHandle(slot: 3, generation: 1)
        model.receive(.call(waiting, accountID: account.id, remote: "103", incoming: true, phase: .incoming, status: 180))
        for _ in 0..<10 where await engine.declinedCalls.isEmpty { await Task.yield() }

        #expect(await engine.declinedCalls == [waiting])
        #expect(model.calls.first(where: { $0.handle == waiting })?.locallyDeclined == true)
    }

    @Test func mediaPauseRunsOncePerStartedCallAndRespectsPreference() async {
        let engine = TestEngine(acceptCalls: true)
        var pauseCount = 0
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            authorizeMicrophone: { true },
            initialPauseMediaDuringCalls: true,
            pauseMediaPlayback: { pauseCount += 1 }
        )
        let account = PhoneAccount()
        model.snapshot.accounts = [account]
        model.selectedAccountID = account.id
        model.ready = true
        model.registrations[account.id] = .registered
        model.dialText = "101"

        let first = await model.dial()
        #expect(first != nil)
        #expect(pauseCount == 1)
        if let first {
            model.receive(.call(first, accountID: account.id, remote: "101", incoming: false, phase: .ringing, status: 180))
        }
        #expect(pauseCount == 1)

        model.setPauseMediaDuringCalls(false)
        model.dialText = "102"
        #expect(await model.dial() != nil)
        #expect(pauseCount == 1)
    }

    @Test func privacySensitiveIntegrationsRequireOptInByDefault() async {
        let lookup = TestPublicCallerLookup(identity: PublicCallerIdentity(
            name: "Example Company", matchedNumber: "+4980212083234", exact: true
        ))
        let model = PhoneModel(
            engine: TestEngine(),
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            publicCallerLookup: lookup
        )

        #expect(!model.pauseMediaDuringCalls)
        #expect(!model.publicCallerLookupEnabled)
        #expect(!model.canUsePublicCallerLookup)
        await model.resolvePublicCallerName("+4980212083234")
        #expect(await lookup.requests.isEmpty)
    }

    @Test func defaultModelFailsClosedForPaidFeatures() {
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository())
        #expect(!model.purchases.hasProAccess)
        #expect(!model.purchases.access.permits(.additionalLines))
        #expect(!model.purchases.access.permits(.callReminders))
    }

    @Test func deniedMicrophoneNeverStartsCallAndPreservesDestination() async {
        let engine = TestEngine()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(),
                               authorizeMicrophone: { false })
        var account = PhoneAccount(); account.domain = "sip.example.com"
        model.snapshot.accounts = [account]; model.selectedAccountID = account.id
        model.ready = true; model.registrations[account.id] = .registered; model.dialText = "123"
        #expect(await model.dial() == nil)
        #expect(await engine.callCount == 0)
        #expect(model.dialText == "123")
        #expect(model.errorMessage == AppError.microphoneDenied.errorDescription)
        #expect(!model.callOperationPending)
        await model.shutdown()
    }

    @Test func staleRegistrationStopsCallBeforeAudioAndPlaysFailureSignal() async {
        let engine = TestEngine(acceptCalls: true, registrationAvailable: false)
        let tones = TestTones()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(),
                               dialTones: tones, authorizeMicrophone: { true })
        let account = PhoneAccount(name: "VPN", username: "test", domain: "sip.vpn.example")
        model.snapshot.accounts = [account]
        model.selectedAccountID = account.id
        model.ready = true
        model.registrations[account.id] = .registered
        model.dialText = "123"

        #expect(await model.dial() == nil)
        #expect(await engine.registrationVerificationCount == 1)
        #expect(await engine.callCount == 0)
        #expect(await engine.setAudioCount == 0)
        #expect(model.registrations[account.id] == .offline)
        #expect(model.dialText == "123")
        #expect(model.errorMessage == AppError.lineUnavailable.errorDescription)
        #expect(tones.callFailureCount == 1)
    }

    @Test func outgoingCallVerificationKeepsAHealthyLineGreen() async throws {
        let engine = TestEngine(acceptCalls: true, registrationVerificationDelay: .milliseconds(100))
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(),
                               authorizeMicrophone: { true })
        let account = PhoneAccount(name: "Office", username: "office", domain: "sip.example.com")
        model.snapshot.accounts = [account]
        model.selectedAccountID = account.id
        model.registrations[account.id] = .registered
        model.ready = true
        model.dialText = "123"

        let call = Task { await model.dial() }
        try await Task.sleep(for: .milliseconds(25))
        #expect(model.registrations[account.id] == .registered)
        #expect(await call.value != nil)
        #expect(model.registrations[account.id] == .registered)
    }

    @Test func holdMusicPersistsRollsBackAndCannotChangeDuringCall() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "telefonx-music-settings-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioFileStore(directory: root)
        let music = AudioAsset(name: "Testton")
        try #require(DialTone.waveData(for: "1")).write(to: store.url(for: music))
        let engine = TestEngine(), repository = MemoryRepository()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository,
                               audioFiles: store, purchases: testProPurchases())
        model.ready = true
        try await model.saveHoldMusic(music)
        #expect(repository.value.holdMusic == music)
        #expect(await engine.configuredMusic == store.url(for: music))

        let replacement = AudioAsset(name: "Neuer Testton")
        try #require(DialTone.waveData(for: "2")).write(to: store.url(for: replacement))
        try await model.saveHoldMusic(replacement)
        #expect(repository.value.holdMusic == replacement)
        #expect(!store.exists(music))
        #expect(store.exists(replacement))

        let rejected = AudioAsset(name: "Nicht gespeichert")
        try #require(DialTone.waveData(for: "3")).write(to: store.url(for: rejected))
        repository.failSave = true
        do { try await model.saveHoldMusic(rejected); Issue.record("Failed persistence accepted") } catch { }
        #expect(model.snapshot.holdMusic == replacement)
        #expect(await engine.configuredMusic == store.url(for: replacement))
        #expect(!store.exists(rejected))
        #expect(store.exists(replacement))
        #expect(!model.configurationBusy)
        repository.failSave = false
        model.calls = [CallSession(handle: CallHandle(slot: 0, generation: 1), accountID: UUID(), remote: "101", incoming: false, phase: .connected)]
        do { try await model.saveHoldMusic(nil); Issue.record("Changed music during call") } catch { }
        #expect(model.snapshot.holdMusic == replacement)
        model.calls = []
        try await model.saveHoldMusic(nil)
        #expect(repository.value.holdMusic == nil)
        #expect(await engine.configuredMusic == nil)
        #expect(!store.exists(replacement))
        await model.shutdown()
    }

    @Test func removingHoldMusicRetainsTheSameFileWhenARingtoneUsesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "telefonx-shared-audio-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioFileStore(directory: root)
        let shared = AudioAsset(name: "Gemeinsam")
        try #require(DialTone.waveData(for: "1")).write(to: store.url(for: shared))
        var account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        account.ringtone = .file(shared)
        let repository = MemoryRepository()
        repository.value.accounts = [account]
        repository.value.holdMusic = shared
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(),
                               repository: repository, audioFiles: store)

        try await model.saveHoldMusic(nil)

        #expect(model.snapshot.holdMusic == nil)
        #expect(store.exists(shared))
    }

    @Test func bulkUnblockCommitsOnceAndPreservesUnrelatedRules() {
        let repository = MemoryRepository()
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let other = BlockRule(number: "103")
        model.snapshot.blocks = [BlockRule(number: "+4930123456"), BlockRule(number: "102"), other]
        let original = model.snapshot
        repository.failSave = true
        model.unblock(["+49 30 123456", "102"])
        #expect(model.snapshot == original)
        #expect(repository.saveCount == 0)
        repository.failSave = false
        model.unblock(["+49 30 123456", "102", "102"])
        #expect(model.snapshot.blocks == [other])
        #expect(repository.saveCount == 1)
        model.unblock(["102"])
        #expect(repository.saveCount == 1)
    }

    @Test func bulkFavoritesPreserveExistingOrderAndCommitAtomically() throws {
        let repository = MemoryRepository()
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let existing = PhoneContact(name: "Existing", numbers: ["101", "201"], favorite: true,
                                    favoriteNumber: "201", favoriteOrder: 0)
        let added = PhoneContact(name: "Added", numbers: ["102"])
        let untouched = PhoneContact(name: "Untouched", numbers: ["103"])
        model.snapshot.contacts = [added, untouched, existing]
        let original = model.snapshot
        repository.failSave = true
        #expect(throws: TestFailure.self) { try model.addContactsToFavorites([existing.id, added.id]) }
        #expect(model.snapshot == original)
        repository.failSave = false
        try model.addContactsToFavorites([existing.id, added.id, UUID()])
        #expect(ContactFavorites.ordered(model.snapshot.contacts).map(\.id) == [existing.id, added.id])
        #expect(model.snapshot.contacts.first { $0.id == existing.id } == existing)
        #expect(model.snapshot.contacts.first { $0.id == untouched.id } == untouched)
        #expect(model.snapshot.contacts.first { $0.id == added.id }?.favoriteNumber == "102")
        #expect(repository.saveCount == 1)
        try model.addContactsToFavorites([existing.id, added.id])
        #expect(repository.saveCount == 1)
    }

    @Test func favoritesCommitOnlySelectionAndPreserveCurrentContactFields() throws {
        let repository = MemoryRepository(), model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let first = PhoneContact(name: "Alex", numbers: ["101", "201"], notes: "Aktuelle Notiz", photoData: Data([1, 2, 3]))
        let second = PhoneContact(name: "Sam", numbers: ["102"])
        model.snapshot.contacts = [first, second]
        try model.saveFavorites([FavoriteChoice(id: second.id, number: "102"), FavoriteChoice(id: first.id, number: "201")])
        #expect(ContactFavorites.ordered(model.snapshot.contacts).map(\.id) == [second.id, first.id])
        #expect(model.snapshot.contacts[0].notes == first.notes)
        #expect(model.snapshot.contacts[0].photoData == first.photoData)
        #expect(ContactFavorites.number(for: model.snapshot.contacts[0]) == "201")
        try model.saveFavorites([])
        #expect(model.snapshot.contacts.allSatisfy { !$0.favorite && $0.favoriteOrder == nil && $0.favoriteNumber == nil })
        #expect(model.snapshot.contacts == [first, second])
        #expect(repository.saveCount == 2)
        #expect(repository.value == model.snapshot)
    }

    @Test func staleOrDuplicateFavoriteChoiceAndFailedSaveNeverMutateSnapshot() throws {
        let repository = MemoryRepository(), model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let contact = PhoneContact(name: "Alex", numbers: ["101"])
        model.snapshot.contacts = [contact]
        let original = model.snapshot, choice = FavoriteChoice(id: contact.id, number: "101")
        for choices in [[choice, choice], [FavoriteChoice(id: UUID(), number: "101")],
                        [FavoriteChoice(id: contact.id, number: "201")], [FavoriteChoice(id: contact.id, number: nil)]] {
            #expect(throws: ContactActionError.self) { try model.saveFavorites(choices) }
            #expect(model.snapshot == original)
        }
        repository.failSave = true
        #expect(throws: TestFailure.self) { try model.saveFavorites([choice]) }
        #expect(model.snapshot == original)
        #expect(repository.saveCount == 0)
    }

    @Test func contactFavoriteToggleAppendsAfterLegacyAndRetainsChosenNumberOnEdit() throws {
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository())
        model.snapshot.contacts = [PhoneContact(name: "Sam", numbers: ["102"], favorite: true),
                                   PhoneContact(name: "Robin", numbers: ["103"], favorite: true)]
        var new = PhoneContact(name: "Alex", numbers: ["101", "201"], favorite: true, favoriteNumber: "201")
        try model.saveContact(new)
        #expect(ContactFavorites.ordered(model.snapshot.contacts).map(\.name) == ["Robin", "Sam", "Alex"])
        new = try #require(model.snapshot.contacts.last); new.notes = "Bearbeitet"
        try model.saveContact(new)
        #expect(model.snapshot.contacts.last?.favoriteOrder == 2)
        #expect(model.snapshot.contacts.last?.favoriteNumber == "201")
        new.favorite = false; try model.saveContact(new)
        #expect(model.snapshot.contacts.last?.favoriteOrder == nil)
        #expect(model.snapshot.contacts.last?.favoriteNumber == nil)
    }

    @Test func addNumberIsNormalizedIdempotentAndPreservesContact() throws {
        let repository = MemoryRepository(), model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let contact = PhoneContact(name: "Alex", numbers: ["101"], notes: "Bleibt", favorite: true, photoData: Data([1]), favoriteNumber: "101", favoriteOrder: 0)
        model.snapshot.contacts = [contact]
        try model.addNumber("0711 1234567", to: contact.id)
        var expected = contact
        expected.phoneNumbers = [ContactPhoneNumber(value: "101", label: .other),
                                 ContactPhoneNumber(value: "07111234567", label: .other)]
        #expect(model.snapshot.contacts == [expected])
        try model.addNumber("+497111234567", to: contact.id)
        #expect(model.snapshot.contacts == [expected])
        #expect(repository.saveCount == 1)
        #expect(throws: ContactActionError.self) { try model.addNumber("105", to: UUID()) }
        #expect(throws: (any Error).self) { try model.addNumber("anonymous", to: contact.id) }
        model.snapshot.contacts[0].numbers = (100..<120).map(String.init)
        #expect(throws: ContactActionError.self) { try model.addNumber("999", to: contact.id) }
        #expect(repository.saveCount == 1)
    }

    @Test func deletingHistoryRemovesOnlyExactEntryAndRollsBackOnStorageFailure() throws {
        let repository = MemoryRepository(), model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let call = CallSession(handle: CallHandle(slot: 1, generation: 1), accountID: UUID(), remote: "101", incoming: false, phase: .connected)
        let first = CallRecord(session: call, accountName: "Test")
        var second = first; second.id = UUID()
        model.snapshot.history = [first, second]
        model.snapshot.contacts = [PhoneContact(name: "Alex", numbers: ["101"])]
        model.snapshot.blocks = [BlockRule(number: "102")]; model.calls = [call]
        var expected = model.snapshot; expected.history = [second]
        repository.failSave = true
        #expect(throws: TestFailure.self) { try model.deleteHistoryRecords([first.id]) }
        #expect(model.snapshot.history == [first, second])
        repository.failSave = false
        try model.deleteHistoryRecords([first.id])
        #expect(model.snapshot == expected)
        #expect(model.calls.map(\.id) == [call.id])
        #expect(model.calls.first?.phase == .connected)
        #expect(model.calls.first?.remote == "101")
        try model.deleteHistoryRecords([first.id])
        #expect(model.snapshot == expected)
    }

    @Test func bulkDeletionCommitsEachSelectionAtomically() throws {
        let repository = MemoryRepository()
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let call = CallSession(handle: CallHandle(slot: 1, generation: 1), accountID: UUID(),
                               remote: "101", incoming: false, phase: .connected)
        let first = CallRecord(session: call, accountName: "Test")
        var second = first; second.id = UUID()
        var third = first; third.id = UUID()
        let alex = PhoneContact(name: "Alex", numbers: ["101"])
        let sam = PhoneContact(name: "Sam", numbers: ["102"])
        let robin = PhoneContact(name: "Robin", numbers: ["103"])
        model.snapshot.history = [first, second, third]
        model.snapshot.contacts = [alex, sam, robin]

        try model.deleteHistoryRecords([first.id, third.id])
        #expect(model.snapshot.history == [second])
        #expect(model.snapshot.contacts == [alex, sam, robin])
        #expect(repository.saveCount == 1)

        try model.deleteContacts([alex.id, robin.id])
        #expect(model.snapshot.contacts == [sam])
        #expect(model.snapshot.history == [second])
        #expect(repository.saveCount == 2)
    }

    @Test func explicitHistoryCallPreservesUnrelatedDraftAndSelectedLine() async throws {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(),
                               authorizeMicrophone: { true }, purchases: testProPurchases())
        let selected = PhoneAccount(), original = PhoneAccount()
        model.snapshot.accounts = [selected, original]; model.selectedAccountID = selected.id
        model.ready = true; model.registrations = [selected.id: .registered, original.id: .registered]; model.dialText = "999"
        #expect(model.canCall("101", preferredAccountID: original.id))
        #expect(await model.callNumber("101", preferredAccountID: original.id) != nil)
        #expect(await engine.lastDestination == "101")
        #expect(await engine.lastAccountID == original.id)
        #expect(model.dialText == "999" && model.selectedAccountID == selected.id)
        model.calls = []
        #expect(await model.dial() != nil)
        #expect(await engine.lastDestination == "999")
        #expect(await engine.lastAccountID == selected.id)
        #expect(model.dialText.isEmpty)
    }

    @Test func lockedDialingRulesNeverAffectANewCall() async throws {
        let engine = TestEngine(acceptCalls: true)
        let purchases = PurchaseStore(internalEvaluation: false, productIDs: [])
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            authorizeMicrophone: { true },
            purchases: purchases
        )
        let selected = PhoneAccount(name: "Selected")
        let ruleTarget = PhoneAccount(name: "Rule Target")
        model.snapshot.accounts = [selected, ruleTarget]
        model.snapshot.dialRules = [DialRule(prefix: "0173", accountID: ruleTarget.id)]
        model.selectedAccountID = selected.id
        model.ready = true
        model.registrations = [selected.id: .registered, ruleTarget.id: .registered]

        #expect(await model.callNumber("01731234567", preferredAccountID: selected.id) != nil)
        #expect(await engine.lastAccountID == selected.id)
    }

    @Test func unlockedDialingRuleRoutesNewCallThroughLongestMatchingRegisteredLine() async throws {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            authorizeMicrophone: { true },
            purchases: testProPurchases()
        )
        let selected = PhoneAccount(name: "Selected")
        let national = PhoneAccount(name: "National")
        let mobile = PhoneAccount(name: "Mobile")
        model.snapshot.accounts = [selected, national, mobile]
        model.snapshot.dialRules = [
            DialRule(prefix: "0", accountID: national.id),
            DialRule(prefix: "0173", accountID: mobile.id)
        ]
        model.selectedAccountID = selected.id
        model.ready = true
        model.registrations = [selected.id: .registered, national.id: .registered, mobile.id: .registered]

        #expect(await model.callNumber("01731234567", preferredAccountID: selected.id) != nil)
        #expect(await engine.lastDestination == "01731234567")
        #expect(await engine.lastAccountID == mobile.id)
    }

    @Test func temporaryCallerIDSuppressionIsConsumedOnlyByAStartedCall() async {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(), authorizeMicrophone: { true })
        let account = PhoneAccount()
        model.snapshot.accounts = [account]; model.selectedAccountID = account.id
        model.ready = true; model.registrations = [account.id: .registered]; model.dialText = "101"

        model.toggleCallerIDSuppressionForNextCall()
        #expect(model.callerIDSuppressionIsActive)
        #expect(await model.dial() != nil)

        #expect(await engine.lastSuppressCallerID == true)
        #expect(!model.suppressCallerIDOnce)
        #expect(!model.callerIDSuppressionIsActive)
    }

    @Test func temporaryCallerIDSuppressionSurvivesFailureAndPermanentSettingIsReadOnly() async {
        let engine = TestEngine(acceptCalls: true, registrationAvailable: false)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(), authorizeMicrophone: { true })
        var account = PhoneAccount()
        model.snapshot.accounts = [account]; model.selectedAccountID = account.id
        model.ready = true; model.registrations = [account.id: .registered]

        model.toggleCallerIDSuppressionForNextCall()
        #expect(await model.callNumber("101", preferredAccountID: account.id) == nil)
        #expect(model.suppressCallerIDOnce)
        #expect(await engine.callCount == 0)

        model.suppressCallerIDOnce = false
        account.suppressCallerID = true
        model.snapshot.accounts = [account]
        #expect(model.selectedAccountAlwaysSuppressesCallerID)
        #expect(model.callerIDSuppressionIsActive)
        model.toggleCallerIDSuppressionForNextCall()
        #expect(!model.suppressCallerIDOnce)
        #expect(model.callerIDSuppressionIsActive)
    }

    @Test func listCallPreparesWhileIdleAndStartsConsultationDuringCall() async throws {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(), authorizeMicrophone: { true })
        let account = PhoneAccount()
        model.snapshot.accounts = [account]; model.selectedAccountID = account.id
        model.ready = true; model.registrations = [account.id: .registered]

        #expect(await model.performListCall("101", preferredAccountID: account.id) == nil)
        #expect(model.dialText == "101")
        #expect(await engine.callCount == 0)

        let original = CallSession(handle: .init(slot: 7, generation: 1), accountID: account.id,
                                   remote: "100", incoming: false, phase: .connected)
        model.calls = [original]
        #expect(await model.performListCall("102", preferredAccountID: account.id) != nil)
        #expect(await engine.holdRequests == [original.handle])
        #expect(await engine.lastDestination == "102")
        #expect(model.dialText == "101")
    }

    @Test func listCallsCanStartImmediatelyWhenEnabled() async {
        let engine = TestEngine(acceptCalls: true)
        var persistedValue: Bool?
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            authorizeMicrophone: { true },
            persistAutomaticallyStartListCalls: { persistedValue = $0 }
        )
        let account = PhoneAccount()
        model.snapshot.accounts = [account]
        model.selectedAccountID = account.id
        model.ready = true
        model.registrations = [account.id: .registered]

        #expect(!model.automaticallyStartListCalls)
        model.setAutomaticallyStartListCalls(true)
        #expect(model.automaticallyStartListCalls)
        #expect(persistedValue == true)

        #expect(await model.performListCall("101", preferredAccountID: account.id) != nil)
        #expect(await engine.callCount == 1)
        #expect(await engine.lastDestination == "101")
        #expect(model.dialText.isEmpty)
    }

    @Test func invalidAutomaticListCallNeverDialsAnExistingDraft() async {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            authorizeMicrophone: { true },
            initialAutomaticallyStartListCalls: true
        )
        let account = PhoneAccount()
        model.snapshot.accounts = [account]
        model.selectedAccountID = account.id
        model.ready = true
        model.registrations = [account.id: .registered]
        model.dialText = "100"

        #expect(await model.performListCall("not a destination", preferredAccountID: account.id) == nil)
        #expect(await engine.callCount == 0)
        #expect(model.dialText == "100")
    }

    @Test func automaticListCallsDoNotChangeReminderCallBehavior() async {
        let engine = TestEngine(acceptCalls: true)
        let account = PhoneAccount()
        let repository = MemoryRepository()
        let reminder = CallReminder(name: "Ada", number: "101", dueAt: Date().addingTimeInterval(3600),
                                    accountID: account.id)
        repository.value.accounts = [account]
        repository.value.reminders = [reminder]
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: repository,
            authorizeMicrophone: { true },
            initialAutomaticallyStartListCalls: true,
            purchases: testProPurchases()
        )
        model.ready = true
        model.registrations = [account.id: .registered]

        await model.performReminderListAction(reminder.id)

        #expect(await engine.callCount == 0)
        #expect(model.dialText == "101")
        #expect(model.preparedReminderID == reminder.id)
    }

    @Test func activeCallForwardsEveryVisibleKeypadDigit() async {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository())
        let call = CallSession(handle: .init(slot: 4, generation: 1), accountID: UUID(),
                               remote: "100", incoming: false, phase: .connected)
        for digit in "123456789*0#" { await model.tone(String(digit), call: call) }
        #expect(await engine.dtmfRequests == Array("123456789*0#").map(String.init))
    }

    @Test func conferenceResumesConsultationAndCanReturnToHeldSplitCalls() async {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository())
        var first = CallSession(handle: CallHandle(slot: 1, generation: 1), accountID: UUID(),
                                remote: "101", incoming: false, phase: .connected)
        first.held = true
        let second = CallSession(handle: CallHandle(slot: 2, generation: 1), accountID: UUID(),
                                 remote: "102", incoming: false, phase: .connected)
        model.calls = [first, second]

        await model.startConference(first, with: second)

        #expect(model.conferenceHandles == [first.handle, second.handle])
        let startedChanges = await engine.conferenceChanges
        #expect(startedChanges.count == 1)
        #expect(startedChanges[0].first == first.handle)
        #expect(startedChanges[0].second == second.handle)
        #expect(startedChanges[0].enabled)
        #expect(await engine.holdChanges.first?.call == first.handle)
        #expect(await engine.holdChanges.first?.held == false)

        await model.endConference(keeping: first)

        #expect(model.conferenceHandles.isEmpty)
        let endedChanges = await engine.conferenceChanges
        #expect(endedChanges.count == 2)
        #expect(!endedChanges[1].enabled)
        #expect(await engine.holdChanges.last?.call == second.handle)
        #expect(await engine.holdChanges.last?.held == true)
    }

    @Test func conferenceStateClearsWhenAParticipantEnds() {
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository())
        let first = CallSession(handle: CallHandle(slot: 1, generation: 1), accountID: UUID(),
                                remote: "101", incoming: false, phase: .connected)
        let second = CallSession(handle: CallHandle(slot: 2, generation: 1), accountID: UUID(),
                                 remote: "102", incoming: false, phase: .connected)
        model.calls = [first, second]
        model.conferenceHandles = [first.handle, second.handle]

        model.receive(.call(first.handle, accountID: first.accountID, remote: first.remote,
                            incoming: false, phase: .ended, status: 200))

        #expect(model.conferenceHandles.isEmpty)
        #expect(model.activeCalls.map(\.handle) == [second.handle])
    }

    @Test func resumingConferenceParticipantDoesNotHoldItsPeer() async {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository())
        var first = CallSession(handle: CallHandle(slot: 1, generation: 1), accountID: UUID(),
                                remote: "101", incoming: false, phase: .connected)
        first.held = true
        let second = CallSession(handle: CallHandle(slot: 2, generation: 1), accountID: UUID(),
                                 remote: "102", incoming: false, phase: .connected)
        model.calls = [first, second]
        model.conferenceHandles = [first.handle, second.handle]

        await model.hold(first)

        let changes = await engine.holdChanges
        #expect(changes.count == 1)
        #expect(changes[0].call == first.handle)
        #expect(changes[0].held == false)
        #expect(await engine.holdRequests.isEmpty)
    }

    @Test func emptyDialActionUsesTheSelectedLinesLatestOutgoingCall() async throws {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(
            engine: engine,
            credentials: EmptyCredentials(),
            repository: MemoryRepository(),
            authorizeMicrophone: { true }
        )
        let selected = PhoneAccount()
        let historical = PhoneAccount()
        model.snapshot.accounts = [selected, historical]
        model.selectedAccountID = selected.id
        model.ready = true
        model.registrations = [selected.id: .registered, historical.id: .registered]

        var selectedOutgoing = CallSession(
            handle: .init(slot: 1, generation: 1),
            accountID: selected.id,
            remote: "055112345",
            incoming: false,
            phase: .connected,
            startedAt: Date(timeIntervalSince1970: 50)
        )
        selectedOutgoing.answeredAt = selectedOutgoing.startedAt
        var otherLineOutgoing = CallSession(
            handle: .init(slot: 2, generation: 1),
            accountID: historical.id,
            remote: "01731234567",
            incoming: false,
            phase: .connected,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        otherLineOutgoing.answeredAt = otherLineOutgoing.startedAt
        var newerIncoming = CallSession(
            handle: .init(slot: 3, generation: 1),
            accountID: selected.id,
            remote: "999",
            incoming: true,
            phase: .connected,
            startedAt: Date(timeIntervalSince1970: 200)
        )
        newerIncoming.answeredAt = newerIncoming.startedAt
        model.snapshot.history = [
            CallRecord(session: newerIncoming, accountName: "Aktuell"),
            CallRecord(session: otherLineOutgoing, accountName: "Historisch"),
            CallRecord(session: selectedOutgoing, accountName: "Selected")
        ]

        #expect(model.canUseDialAction)
        #expect(model.hasRedialTarget)
        #expect(await model.performDialAction() == nil)
        #expect(model.dialText == "055112345")
        #expect(model.selectedAccountID == selected.id)
        #expect(await engine.callCount == 0)
        #expect(model.canDial)

        #expect(await model.performDialAction() != nil)
        #expect(await engine.callCount == 1)
        #expect(await engine.lastDestination == "055112345")
        #expect(await engine.lastAccountID == selected.id)
        #expect(model.dialText.isEmpty)

        model.selectedAccountID = historical.id
        #expect(model.hasRedialTarget)
        #expect(await model.performDialAction() == nil)
        #expect(model.dialText == "01731234567")

        model.dialText = ""
        model.registrations[historical.id] = .failed(503)
        model.snapshot.dialRules = [DialRule(prefix: "0173", accountID: selected.id)]
        #expect(model.hasRedialTarget)
        #expect(!model.canUseDialAction)
        #expect(await model.performDialAction() == nil)
        #expect(model.dialText.isEmpty)
    }

    @Test func accountReorderCommitsOnlyTheFinalOrder() {
        let repository = MemoryRepository()
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository)
        let first = PhoneAccount(name: "A", username: "a", domain: "sip.example.com", sortIndex: 0)
        let second = PhoneAccount(name: "B", username: "b", domain: "sip.example.com", sortIndex: 1)
        let third = PhoneAccount(name: "C", username: "c", domain: "sip.example.com", sortIndex: 2)
        model.snapshot.accounts = [first, second, third]

        model.moveAccount(first.id, over: third.id)

        #expect(model.snapshot.accounts.map(\.id) == [second.id, third.id, first.id])
        #expect(model.snapshot.accounts.map(\.sortIndex) == [0, 1, 2])
        #expect(repository.saveCount == 1)

        model.moveAccount(first.id, over: second.id)

        #expect(model.snapshot.accounts.map(\.id) == [first.id, second.id, third.id])
        #expect(repository.saveCount == 2)
    }

    @Test func explicitCallRejectsInvalidOfflineBusyAndDeniedMicrophone() async {
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: MemoryRepository(), authorizeMicrophone: { false })
        let account = PhoneAccount()
        model.snapshot.accounts = [account]; model.selectedAccountID = account.id; model.ready = true; model.dialText = "999"
        #expect(!model.canCall("101", preferredAccountID: account.id))
        #expect(await model.callNumber("101", preferredAccountID: account.id) == nil)
        model.registrations[account.id] = .registered
        #expect(!model.canCall("anonymous", preferredAccountID: account.id))
        #expect(await model.callNumber("anonymous", preferredAccountID: account.id) == nil)
        model.configurationBusy = true
        #expect(!model.canCall("101", preferredAccountID: account.id))
        #expect(await model.callNumber("101", preferredAccountID: account.id) == nil)
        model.configurationBusy = false
        #expect(await model.callNumber("101", preferredAccountID: account.id) == nil)
        #expect(await engine.callCount == 0)
        #expect(model.dialText == "999")
    }

    @Test func publicCallerLookupUpdatesUnknownNamesAndLocalContactsKeepPriority() async {
        let lookup = TestPublicCallerLookup(identity: PublicCallerIdentity(
            name: "Hetzner Online GmbH", matchedNumber: "+493745744470", exact: false
        ))
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository(),
                               publicCallerLookup: lookup, initialPublicCallerLookupEnabled: true,
                               purchases: testProPurchases())

        #expect(model.displayName("+49-3745-74447-100") == "+49-3745-74447-100")
        await model.resolvePublicCallerName("+49-3745-74447-100")
        #expect(model.displayName("+49-3745-74447-100") == "Hetzner Online GmbH")
        #expect(await lookup.requests == ["+49374574447100"])

        model.snapshot.contacts = [PhoneContact(name: "Hetzner Support", numbers: ["+49374574447100"])]
        #expect(model.displayName("+49-3745-74447-100") == "Hetzner Support")
    }

    @Test func disablingPublicCallerLookupClearsNamesAndPersistsPreference() async {
        let lookup = TestPublicCallerLookup(identity: PublicCallerIdentity(
            name: "Hetzner Online GmbH", matchedNumber: "+493745744470", exact: false
        ))
        var persisted: Bool?
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository(),
                               publicCallerLookup: lookup,
                               initialPublicCallerLookupEnabled: true,
                               persistPublicCallerLookupEnabled: { persisted = $0 },
                               purchases: testProPurchases())
        await model.resolvePublicCallerName("+49374574447100")
        #expect(model.displayName("+49374574447100") == "Hetzner Online GmbH")

        model.setPublicCallerLookupEnabled(false)

        #expect(persisted == false)
        #expect(model.displayName("+49374574447100") == "+49374574447100")
        await model.resolvePublicCallerName("+49374574447100")
        #expect(await lookup.requests.count == 1)
    }

    @Test func disabledInFlightPublicLookupDoesNotPreventRetryAfterEnabling() async {
        let lookup = DeferredPublicCallerLookup()
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository(),
                               publicCallerLookup: lookup, initialPublicCallerLookupEnabled: true,
                               purchases: testProPurchases())
        let first = Task { await model.resolvePublicCallerName("+49374574447100") }
        while await lookup.requests == 0 { await Task.yield() }
        model.setPublicCallerLookupEnabled(false)
        model.setPublicCallerLookupEnabled(true)
        await lookup.resume()
        await first.value
        #expect(model.publicCallerNames.isEmpty)
        await model.resolvePublicCallerName("+49374574447100")
        #expect(await lookup.requests == 2)
    }

    @Test func cancelledPublicCallerLookupIsNotCachedAsAMiss() async {
        let lookup = TestPublicCallerLookup(identity: nil, suspendFirstRequest: true)
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository(),
                               publicCallerLookup: lookup, initialPublicCallerLookupEnabled: true,
                               purchases: testProPurchases())
        let first = Task { await model.resolvePublicCallerName("+49374574447100") }
        while await lookup.requests.isEmpty { await Task.yield() }

        first.cancel()
        await first.value
        await model.resolvePublicCallerName("+49374574447100")

        #expect(await lookup.requests.count == 2)
    }

    @Test func appleContactsStayReadOnlyResolveNamesAndYieldToLocalContacts() async throws {
        let counter = AppleContactsFetchCounter()
        let provider = TestAppleContactsProvider(authorization: .authorized, contacts: [
            AppleContact(id: "apple-alex", name: "Apple Alex", company: "Apple Büro",
                         phoneNumbers: [ContactPhoneNumber(value: "101", label: .work),
                                        ContactPhoneNumber(value: "102", label: .mobile)], photoData: nil)
        ], counter: counter)
        var persisted: Bool?
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository(),
                               appleContactsProvider: provider,
                               persistAppleContactsEnabled: { persisted = $0 })
        model.snapshot.contacts = [PhoneContact(name: "Lokaler Alex", numbers: ["101"])]

        await model.setAppleContactsEnabled(true)

        #expect(persisted == true)
        #expect(await counter.count == 1)
        #expect(model.appleContacts.count == 1)
        #expect(model.visibleAppleContacts.first?.numbers == ["102"])
        #expect(model.displayName("101") == "Lokaler Alex")
        #expect(model.displayName("102") == "Apple Alex")
        #expect(model.snapshot.contacts.count == 1)

        let copy = try #require(model.visibleAppleContacts.first?.localCopy())
        try model.saveContact(copy)
        #expect(model.snapshot.contacts.count == 2)
        #expect(model.visibleAppleContacts.isEmpty)

        await model.setAppleContactsEnabled(false)
        #expect(persisted == false)
        #expect(model.appleContacts.isEmpty)
    }

    @Test func deniedAppleContactAccessIsReportedWithoutFetchingOrChangingLocalData() async {
        let counter = AppleContactsFetchCounter()
        let provider = TestAppleContactsProvider(authorization: .denied, contacts: [], counter: counter)
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: MemoryRepository(),
                               appleContactsProvider: provider)
        model.snapshot.contacts = [PhoneContact(name: "Lokal", numbers: ["101"])]

        await model.setAppleContactsEnabled(true)

        #expect(model.appleContactsEnabled)
        #expect(model.appleContactsAuthorization == .denied)
        #expect(model.appleContacts.isEmpty)
        #expect(await counter.count == 0)
        #expect(model.snapshot.contacts.map(\.name) == ["Lokal"])
    }

    @Test func callRemindersPersistScheduleCompleteSnoozeAndPrepareWithoutAutoCalling() async throws {
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        let repository = MemoryRepository()
        repository.value.accounts = [account]
        let recorder = ReminderScheduleRecorder()
        let engine = TestEngine()
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository,
                               scheduleReminderNotification: { reminder, timing, request in
                                   await recorder.record(reminder, timing: timing, requestsAuthorization: request)
                               }, purchases: testProPurchases())
        let reminder = CallReminder(name: "Ada", number: "123", note: "Angebot",
                                    dueAt: Date().addingTimeInterval(3600), accountID: account.id)

        try model.saveReminder(reminder)
        while await recorder.entries.isEmpty { await Task.yield() }
        #expect(repository.value.reminders == [reminder])
        #expect(await recorder.entries.first?.requestsAuthorization == true)
        #expect(await recorder.entries.first?.timing == .atTime)

        model.prepareReminderCall(reminder.id)
        #expect(model.dialText == "123")
        #expect(model.selectedAccountID == account.id)
        #expect(await engine.callCount == 0)

        try model.snoozeReminder(reminder.id, by: 600)
        #expect(model.snapshot.reminders[0].dueAt > Date())
        try model.completeReminder(reminder.id)
        #expect(model.snapshot.reminders[0].completedAt != nil)
        try model.deleteReminders([reminder.id])
        #expect(model.snapshot.reminders.isEmpty)
    }

    @Test func reminderNotificationsUseGlobalDefaultAndAllowPerReminderOverride() async throws {
        let repository = MemoryRepository()
        let recorder = ReminderScheduleRecorder()
        var persisted: [CallReminderNotificationTiming] = []
        let model = PhoneModel(
            engine: TestEngine(), credentials: EmptyCredentials(), repository: repository,
            scheduleReminderNotification: { reminder, timing, request in
                await recorder.record(reminder, timing: timing, requestsAuthorization: request)
            },
            initialReminderNotificationTiming: .tenMinutesBefore,
            persistReminderNotificationTiming: { persisted.append($0) },
            purchases: testProPurchases()
        )
        var reminder = CallReminder(name: "Ada", number: "123", dueAt: Date().addingTimeInterval(3600))

        try model.saveReminder(reminder)
        while await recorder.entries.count < 1 { await Task.yield() }
        #expect(await recorder.entries.last?.timing == .tenMinutesBefore)

        model.setDefaultReminderNotificationTiming(.fiveMinutesBefore)
        while await recorder.entries.count < 2 { await Task.yield() }
        #expect(persisted == [.fiveMinutesBefore])
        #expect(await recorder.entries.last?.timing == .fiveMinutesBefore)

        reminder.notificationTiming = .atTime
        try model.saveReminder(reminder)
        while await recorder.entries.count < 3 { await Task.yield() }
        #expect(await recorder.entries.last?.timing == .atTime)
    }

    @Test func connectedReminderCallCompletesWhenItEnds() async throws {
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        let repository = MemoryRepository()
        repository.value.accounts = [account]
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository,
                               authorizeMicrophone: { true }, purchases: testProPurchases())
        model.ready = true
        model.registrations[account.id] = .registered
        model.selectedAccountID = account.id
        let reminder = CallReminder(name: "Ada", number: "123", dueAt: Date().addingTimeInterval(-60))
        model.snapshot.reminders = [reminder]

        await model.callReminderNow(reminder.id)
        let handle = try #require(model.calls.first?.handle)
        model.receive(.call(handle, accountID: account.id, remote: "123", incoming: false,
                            phase: .connected, status: 200))
        #expect(model.snapshot.reminders[0].completedAt == nil)
        model.receive(.call(handle, accountID: account.id, remote: "123", incoming: false,
                            phase: .ended, status: 200))

        #expect(model.snapshot.reminders[0].completedAt != nil)
    }

    @Test func unansweredReminderCallStaysOpen() async throws {
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        let repository = MemoryRepository()
        repository.value.accounts = [account]
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository,
                               authorizeMicrophone: { true }, purchases: testProPurchases())
        model.ready = true
        model.registrations[account.id] = .registered
        model.selectedAccountID = account.id
        let reminder = CallReminder(name: "Ada", number: "123", dueAt: Date().addingTimeInterval(3600))
        try model.saveReminder(reminder)

        model.prepareReminderCall(reminder.id)
        await model.dial()
        let handle = try #require(model.calls.first?.handle)
        model.receive(.call(handle, accountID: account.id, remote: "123", incoming: false,
                            phase: .ended, status: 486))

        #expect(model.snapshot.reminders[0].completedAt == nil)
    }

    @Test func pastDueReminderCannotBeSavedOpenOrReopened() throws {
        let repository = MemoryRepository()
        let model = PhoneModel(engine: TestEngine(), credentials: EmptyCredentials(), repository: repository,
                               purchases: testProPurchases())
        let past = Date().addingTimeInterval(-3600)
        let open = CallReminder(name: "Ada", number: "123", dueAt: past)

        #expect(throws: AppError.reminderDateInPast) { try model.saveReminder(open) }
        #expect(model.snapshot.reminders.isEmpty)

        var completed = open
        completed.completedAt = Date()
        try model.saveReminder(completed)
        #expect(model.snapshot.reminders.first?.completedAt != nil)
        #expect(throws: AppError.reminderDateInPast) {
            try model.completeReminder(completed.id, completed: false)
        }
        #expect(model.snapshot.reminders.first?.completedAt != nil)
    }

    @Test func connectedReminderCallBeforeItsDueDateStaysOpen() async throws {
        let account = PhoneAccount(name: "Test", username: "test", domain: "sip.example.com")
        let repository = MemoryRepository()
        repository.value.accounts = [account]
        let engine = TestEngine(acceptCalls: true)
        let model = PhoneModel(engine: engine, credentials: EmptyCredentials(), repository: repository,
                               authorizeMicrophone: { true }, purchases: testProPurchases())
        model.ready = true
        model.registrations[account.id] = .registered
        model.selectedAccountID = account.id
        let reminder = CallReminder(name: "Ada", number: "123", dueAt: Date().addingTimeInterval(3600))
        try model.saveReminder(reminder)

        await model.callReminderNow(reminder.id)
        let handle = try #require(model.calls.first?.handle)
        model.receive(.call(handle, accountID: account.id, remote: "123", incoming: false,
                            phase: .connected, status: 200))
        model.receive(.call(handle, accountID: account.id, remote: "123", incoming: false,
                            phase: .ended, status: 200))

        #expect(model.snapshot.reminders[0].completedAt == nil)
    }

    @Test func reminderNotificationDeliveryDatesRespectTheSelectedLeadTime() throws {
        let dueAt = Date(timeIntervalSince1970: 10_000)
        let reminder = CallReminder(name: "Ada", number: "123", dueAt: dueAt)

        #expect(CallReminderNotifications.deliveryDate(for: reminder, timing: .none) == nil)
        #expect(CallReminderNotifications.deliveryDate(for: reminder, timing: .atTime) == dueAt)
        #expect(CallReminderNotifications.deliveryDate(for: reminder, timing: .fiveMinutesBefore)
                == dueAt.addingTimeInterval(-300))
        #expect(CallReminderNotifications.deliveryDate(for: reminder, timing: .tenMinutesBefore)
                == dueAt.addingTimeInterval(-600))
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return await condition()
    }

}

private actor ReminderScheduleRecorder {
    struct Entry: Sendable {
        let reminder: CallReminder
        let timing: CallReminderNotificationTiming
        let requestsAuthorization: Bool
    }
    private(set) var entries: [Entry] = []
    func record(_ reminder: CallReminder, timing: CallReminderNotificationTiming, requestsAuthorization: Bool) {
        entries.append(Entry(reminder: reminder, timing: timing, requestsAuthorization: requestsAuthorization))
    }
}

@MainActor private func testProPurchases() -> PurchaseStore {
    PurchaseStore(internalEvaluation: true, productIDs: [])
}

@MainActor private final class MemoryRepository: PhoneRepository {
    var value = AppSnapshot()
    var saveCount = 0
    var failSave = false
    let failLoad: Bool
    init(failLoad: Bool = false) { self.failLoad = failLoad }
    func load() throws -> AppSnapshot {
        if failLoad { throw TestFailure.unreadable }
        return value
    }
    func save(_ snapshot: AppSnapshot, changes: SnapshotChanges) throws {
        if failSave { throw TestFailure.unreadable }
        try snapshot.validate(); value = snapshot; saveCount += 1
    }
}

private enum TestFailure: Error { case unreadable, unexpectedOperation }
private actor TestPublicCallerLookup: PublicCallerLookingUp {
    let result: PublicCallerIdentity?
    let suspendFirstRequest: Bool
    private(set) var requests: [String] = []
    init(identity: PublicCallerIdentity?, suspendFirstRequest: Bool = false) {
        result = identity
        self.suspendFirstRequest = suspendFirstRequest
    }
    func identity(for number: String) async -> PublicCallerIdentity? {
        requests.append(number)
        if suspendFirstRequest, requests.count == 1 {
            try? await Task.sleep(for: .seconds(30))
        }
        return result
    }
}
private actor DeferredPublicCallerLookup: PublicCallerLookingUp {
    private(set) var requests = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func identity(for number: String) async -> PublicCallerIdentity? {
        requests += 1
        if requests == 1 { await withCheckedContinuation { continuation = $0 } }
        return nil
    }
    func resume() { continuation?.resume(); continuation = nil }
}

private actor AppleContactsFetchCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
private struct TestAppleContactsProvider: AppleContactsProviding {
    let authorization: AppleContactsAuthorization
    let contacts: [AppleContact]
    let counter: AppleContactsFetchCounter
    func authorizationStatus() -> AppleContactsAuthorization { authorization }
    func requestAccess() async throws -> Bool { authorization == .authorized }
    func fetch() async throws -> [AppleContact] {
        await counter.increment()
        return contacts
    }
}
@MainActor private final class TestTones: DialTonePlaying {
    private(set) var callFailureCount = 0
    func play(_ digit: Character, outputUID: String) {}
    func playCallFailure(outputUID: String) { callFailureCount += 1 }
    func stop() {}
}
private struct EmptyCredentials: CredentialStore {
    func password(for id: UUID) throws -> String? { nil }
    func setPassword(_ password: String, for id: UUID) throws { throw TestFailure.unexpectedOperation }
    func deletePassword(for id: UUID) throws { throw TestFailure.unexpectedOperation }
}

private struct PasswordCredentials: CredentialStore {
    func password(for id: UUID) throws -> String? { "secret" }
    func setPassword(_ password: String, for id: UUID) throws { }
    func deletePassword(for id: UUID) throws { }
}

/// No PJSIP instance, sockets, microphone, Keychain or user database in these tests.
private actor TestEngine: TelephonyService {
    nonisolated let events: AsyncStream<TelephonyEvent>
    private let continuation: AsyncStream<TelephonyEvent>.Continuation
    private let stopEvents: [TelephonyEvent]
    private(set) var startCount = 0
    private(set) var callCount = 0
    private(set) var configuredMusic: URL?
    private let acceptCalls: Bool
    private let acceptDeclines: Bool
    private let acceptRegistrations: Bool
    private let registrationAvailable: Bool
    private let registrationVerificationDelay: Duration?
    private let hangupError: EngineError?
    private(set) var declinedCalls: [CallHandle] = []
    private(set) var lastDestination: String?
    private(set) var lastAccountID: UUID?
    private(set) var lastSuppressCallerID: Bool?
    private(set) var holdRequests: [CallHandle] = []
    private(set) var holdChanges: [(call: CallHandle, held: Bool)] = []
    private(set) var releaseCount = 0
    private(set) var conferenceChanges: [(first: CallHandle, second: CallHandle, enabled: Bool)] = []
    private(set) var dtmfRequests: [String] = []
    private(set) var registeredAccounts: [UUID] = []
    private(set) var unregisteredAccounts: [UUID] = []
    private(set) var networkChangeCount = 0
    private(set) var registrationVerificationCount = 0
    private(set) var concurrentRegistrationVerifications = 0
    private(set) var maximumConcurrentRegistrationVerifications = 0
    private(set) var setAudioCount = 0
    init(stopEvents: [TelephonyEvent] = [], acceptCalls: Bool = false, acceptDeclines: Bool = false,
         hangupError: EngineError? = nil, acceptRegistrations: Bool = false,
         registrationAvailable: Bool = true, registrationVerificationDelay: Duration? = nil) {
        let pair = AsyncStream<TelephonyEvent>.makeStream()
        events = pair.stream; continuation = pair.continuation; self.stopEvents = stopEvents
        self.acceptCalls = acceptCalls
        self.acceptDeclines = acceptDeclines
        self.hangupError = hangupError
        self.acceptRegistrations = acceptRegistrations
        self.registrationAvailable = registrationAvailable
        self.registrationVerificationDelay = registrationVerificationDelay
    }
    func start() { startCount += 1 }
    func stop() {
        for event in stopEvents { continuation.yield(event) }
        continuation.finish()
    }
    func register(_ account: PhoneAccount, password: String) throws {
        guard acceptRegistrations else { throw TestFailure.unexpectedOperation }
        registeredAccounts.append(account.id)
    }
    func unregister(_ id: UUID) throws {
        guard acceptRegistrations else { throw TestFailure.unexpectedOperation }
        unregisteredAccounts.append(id)
    }
    func verifyRegistration(_ id: UUID) async -> Bool {
        registrationVerificationCount += 1
        concurrentRegistrationVerifications += 1
        maximumConcurrentRegistrationVerifications = max(
            maximumConcurrentRegistrationVerifications,
            concurrentRegistrationVerifications
        )
        defer { concurrentRegistrationVerifications -= 1 }
        if let registrationVerificationDelay {
            try? await Task.sleep(for: registrationVerificationDelay)
        }
        return registrationAvailable
    }
    func call(_ destination: CallDestination, account: PhoneAccount) throws -> CallHandle {
        callCount += 1
        guard acceptCalls else { throw TestFailure.unexpectedOperation }
        lastDestination = destination.value; lastAccountID = account.id; lastSuppressCallerID = account.suppressCallerID
        return CallHandle(slot: Int32(callCount), generation: 1)
    }
    func answer(_ call: CallHandle) throws { throw TestFailure.unexpectedOperation }
    func hangup(_ call: CallHandle, decline: Bool) throws {
        if let hangupError { throw hangupError }
        guard acceptDeclines && decline else { throw TestFailure.unexpectedOperation }
        declinedCalls.append(call)
    }
    func mute(_ call: CallHandle, muted: Bool) throws { throw TestFailure.unexpectedOperation }
    func hold(_ call: CallHandle, held: Bool) throws {
        guard acceptCalls else { throw TestFailure.unexpectedOperation }
        holdChanges.append((call, held))
        if held { holdRequests.append(call) }
    }
    func setHoldMusic(_ file: URL?) throws { configuredMusic = file }
    func sendDTMF(_ digit: String, call: CallHandle) throws {
        guard acceptCalls else { throw TestFailure.unexpectedOperation }
        dtmfRequests.append(digit)
    }
    func conference(_ first: CallHandle, with second: CallHandle, enabled: Bool) throws {
        guard acceptCalls else { throw TestFailure.unexpectedOperation }
        conferenceChanges.append((first, second, enabled))
    }
    func transfer(_ source: CallHandle, to consultation: CallHandle) throws { throw TestFailure.unexpectedOperation }
    func quality(_ call: CallHandle) throws -> CallQuality { throw TestFailure.unexpectedOperation }
    func audioDevices() -> [AudioDevice] { [] }
    func setAudio(input: Int32, output: Int32) throws {
        setAudioCount += 1
        if !acceptCalls { throw TestFailure.unexpectedOperation }
    }
    func releaseAudio() { releaseCount += 1 }
    func networkChanged() { networkChangeCount += 1 }
}
