import AppKit
import Foundation
import Testing
import TelefonDomain
@testable import TelefonX

@Suite struct PresentationTests {
    @Test func emptyStatesCompensateForHalfTheUnifiedToolbar() {
        #expect(WindowCenteredEmptyStateLayout.unifiedToolbarHeight == 52)
        #expect(WindowCenteredEmptyStateLayout.verticalOffset == -26)
    }

    private func call(_ slot: Int32, incoming: Bool = false, held: Bool = false) -> CallSession {
        var call = CallSession(handle: CallHandle(slot: slot, generation: 1), accountID: UUID(), remote: "101",
                               incoming: incoming, phase: incoming ? .incoming : .connected)
        call.held = held
        if !incoming { call.answeredAt = call.startedAt }
        return call
    }

    @Test func selectionUsesFullHandleAndFallsBackAfterHangup() {
        let held = call(0, held: true), talking = call(1), incoming = call(2, incoming: true)
        #expect(CallPresentation.selected(in: [held, talking, incoming], preferred: talking.handle)?.handle == talking.handle)
        #expect(CallPresentation.selected(in: [held, talking, incoming], preferred: nil)?.handle == incoming.handle)
        #expect(CallPresentation.selected(in: [held, talking], preferred: incoming.handle)?.handle == talking.handle)
        #expect(CallPresentation.selected(in: [held], preferred: CallHandle(slot: 0, generation: 99))?.handle == held.handle)
        var ended = talking; ended.phase = .ended
        #expect(CallPresentation.selected(in: [ended], preferred: ended.handle) == nil)
        #expect(CallPresentation.selected(in: [], preferred: nil) == nil)
    }

    @Test func statusReflectsHoldAndMute() {
        var connected = call(0)
        #expect(CallPresentation.status(connected) == "In Call")
        connected.muted = true
        #expect(CallPresentation.status(connected) == "Microphone Muted")
        #expect(CallPresentation.status(connected, inConference: true) == "Conference · Microphone Muted")
        connected.muted = false
        #expect(CallPresentation.status(connected, inConference: true) == "In Conference")
        connected.held = true
        #expect(CallPresentation.status(connected) == "On Hold")
        #expect(CallPresentation.status(call(1, incoming: true)) == "Incoming Call")
    }

    @Test func conferenceAndTransferActionsRequireExactlyTwoConnectedCalls() {
        let selected = call(0)
        let other = call(1, held: true)
        let third = call(2, held: true)
        let incoming = call(3, incoming: true)

        #expect(CallPresentation.pairedCall(for: selected, in: [selected]) == nil)
        #expect(CallPresentation.pairedCall(for: selected, in: [selected, other])?.handle == other.handle)
        #expect(CallPresentation.pairedCall(for: selected, in: [selected, other, third]) == nil)
        #expect(CallPresentation.pairedCall(for: selected, in: [selected, other, incoming]) == nil)
        #expect(CallPresentation.pairedCall(for: incoming, in: [selected, incoming]) == nil)
    }

    @Test func doNotDisturbToolbarRequiresAConfiguredLine() {
        #expect(!PhoneWorkspaceToolbarPresentation.showsWorkspace(accountCount: 0))
        #expect(PhoneWorkspaceToolbarPresentation.showsWorkspace(accountCount: 1))
        #expect(!PhoneWorkspaceToolbarPresentation.showsDoNotDisturb(accountCount: 0))
        #expect(PhoneWorkspaceToolbarPresentation.showsDoNotDisturb(accountCount: 1))
        #expect(PhoneWorkspaceToolbarPresentation.showsDoNotDisturb(accountCount: 3))
    }

    @Test func filtersComposeAndNeverMutateHistory() {
        var missed = CallRecord(session: call(0, incoming: true), accountName: "Home")
        var answered = CallRecord(session: call(1), accountName: "Home")
        missed.remote = "101"; answered.remote = "102"
        let original = [answered, missed]
        let name: (String) -> String = { $0 == "101" ? "Alex Beispiel" : "Sam Muster" }
        #expect(HistoryPresentation.records(original, filter: .missed, search: " alex ", displayName: name).map(\.id) == [missed.id])
        #expect(HistoryPresentation.records(original, filter: .missed, search: "102", displayName: name).isEmpty)
        #expect(HistoryPresentation.records(original, filter: .all, search: "", displayName: name).count == 2)
        #expect(original == [answered, missed])
        #expect(HistoryPresentation.outcome(answered) == "Outgoing")
    }

    @Test func historyHasStableRecordOrder() {
        var first = CallRecord(session: call(0), accountName: "Home")
        var second = CallRecord(session: call(1), accountName: "Home")
        first.startedAt = Date(timeIntervalSince1970: 100_000)
        second.startedAt = Date(timeIntervalSince1970: 200_000)
        let sorted = HistoryPresentation.records([first, second], filter: .all, search: "", displayName: { $0 })
        #expect(sorted.map(\.id) == [second.id, first.id])
        #expect(sorted.map(\.id) == HistoryPresentation.records([second, first], filter: .all, search: "", displayName: { $0 }).map(\.id))
    }

    @Test func completedReminderRowsHidePendingMetadataAndCallAction() {
        #expect(CallReminderRowPresentation.showsPendingActions(completedAt: nil))
        #expect(!CallReminderRowPresentation.showsPendingActions(completedAt: Date()))
    }

    @Test func endedCallSuggestionUsesAPausableSixtySecondLifetime() {
        #expect(EndedCallSuggestionTimeout.duration == 60)
        #expect(EndedCallSuggestionTimeout.remaining(60, after: 12.5) == 47.5)
        #expect(EndedCallSuggestionTimeout.remaining(60, after: 90) == 0)
        #expect(EndedCallSuggestionTimeout.remaining(60, after: -5) == 60)
    }

    @Test func consultationContactsPutFavoritesFirstAndFilterAllVisibleFields() {
        let favorite = PhoneContact(name: "Zora", company: "Enwikuna", numbers: ["201"], favorite: true)
        let alpha = PhoneContact(name: "Alex", numbers: ["101"], group: "Support")
        let beta = PhoneContact(name: "Berta", company: "Nord", numbers: ["102"])
        #expect(ConsultationContactPresentation.contacts([beta, alpha, favorite], search: "").map(\.id) == [favorite.id, alpha.id, beta.id])
        #expect(ConsultationContactPresentation.contacts([beta, alpha, favorite], search: "support").map(\.id) == [alpha.id])
        #expect(ConsultationContactPresentation.contacts([beta, alpha, favorite], search: " 201 ").map(\.id) == [favorite.id])
    }

    @Test @MainActor func consultationModeControlUsesIconsAndEqualFullWidthSegments() {
        let control = NSSegmentedControl()
        ConsultationModePicker.configure(control)

        #expect(control.segmentCount == 2)
        #expect(control.label(forSegment: 0) == "Dial")
        #expect(control.label(forSegment: 1) == "Contacts")
        #expect(control.image(forSegment: 0) != nil)
        #expect(control.image(forSegment: 1) != nil)
        #expect(control.segmentDistribution == .fillEqually)
        #expect(control.controlSize == .large)
        #expect(control.accessibilityLabel() == "Consult Using")

        let container = ConsultationModePicker.Container()
        #expect(container.intrinsicContentSize.width == NSView.noIntrinsicMetric)
    }

    #if DEBUG
    @Test func previewScenariosOpenTheirIntendedSection() {
        #expect(PreviewScenario.favorites.initialSection == .favorites)
        #expect(PreviewScenario.avatars.initialSection == .contacts)
        #expect(PreviewScenario.reminders.initialSection == .reminders)
        #expect(PreviewScenario.connected.initialSection == .history)
    }

    @Test @MainActor func noLinesPreviewRepresentsAnUnconfiguredApp() {
        let model = PreviewFixtures.makeModel()
        PreviewFixtures.apply(.noLines, to: model)

        #expect(model.snapshot.accounts.isEmpty)
        #expect(model.selectedAccountID == nil)
        #expect(model.registrations.isEmpty)
        #expect(model.activeCalls.isEmpty)
        #expect(model.snapshot.history.isEmpty)
    }

    @Test @MainActor func remindersWithoutLineRetainsContentButCannotShowPhoneWorkspace() {
        let model = PreviewFixtures.makeModel()
        PreviewFixtures.apply(.remindersNoLines, to: model)
        #expect(PreviewScenario.remindersNoLines.initialSection == .reminders)
        #expect(model.snapshot.accounts.isEmpty)
        #expect(model.selectedAccountID == nil)
        #expect(model.registrations.isEmpty)
        #expect(model.activeCalls.isEmpty)
        #expect(!model.snapshot.reminders.isEmpty)
        #expect(model.snapshot.reminders.allSatisfy { $0.accountID == nil })
        #expect(!PhoneWorkspaceToolbarPresentation.showsWorkspace(accountCount: model.snapshot.accounts.count))
    }

    @Test @MainActor func singleRecordPreviewCoversEmptyFilterRoundtrip() throws {
        let model = PreviewFixtures.makeModel()
        PreviewFixtures.apply(.singleRecord, to: model)
        #expect(model.activeCalls.isEmpty)
        let original = try #require(model.snapshot.history.first)
        #expect(model.snapshot.history.count == 1)
        #expect(original.outcome == .answered)
        for _ in 0..<5 {
            #expect(HistoryPresentation.records(model.snapshot.history, filter: .missed, search: "", displayName: model.displayName).isEmpty)
            #expect(HistoryPresentation.records(model.snapshot.history, filter: .all, search: "", displayName: model.displayName) == [original])
            #expect(HistoryPresentation.records(model.snapshot.history, filter: .all, search: "keine-treffer", displayName: model.displayName).isEmpty)
        }
        #expect(model.snapshot.history == [original])
    }

    @Test @MainActor func isolatedPreviewExercisesCallControlsWithoutDevices() async throws {
        let model = PreviewFixtures.makeModel()
        let original = try #require(model.activeCalls.first)
        await model.mute(original)
        #expect(model.activeCalls.first?.muted == true)
        await model.hold(original)
        #expect(model.activeCalls.first?.held == true)
        model.dialText = "102"
        let handle = try #require(await model.dial())
        #expect(model.activeCalls.count == 2)
        #expect(model.activeCalls.last?.handle == handle)
        #expect(model.dialText.isEmpty)
        await model.startConference(original, with: try #require(model.activeCalls.last))
        #expect(model.conferenceHandles == [original.handle, handle])
        await model.endConference(keeping: original)
        #expect(model.conferenceHandles.isEmpty)
        await model.hangup(try #require(model.activeCalls.last))
        #expect(model.activeCalls.count == 1)
        PreviewFixtures.apply(.incoming, to: model)
        await model.answer(try #require(model.activeCalls.first))
        #expect(model.activeCalls.first?.phase == .connected)
        await model.shutdown()
    }

    @Test @MainActor func fiveCallPreviewExercisesOverflowParticipantList() {
        let model = PreviewFixtures.makeModel()
        PreviewFixtures.apply(.fiveCalls, to: model)

        #expect(model.activeCalls.count == 5)
        #expect(model.activeCalls.map(\.remote) == ["101", "102", "103", "104", "105"])
        #expect(model.activeCalls.prefix(4).allSatisfy { $0.held })
        #expect(model.activeCalls.last?.held == false)
        #expect(model.activeCalls.map { model.displayName($0.remote) } ==
                ["Alex Beispiel", "Sam Muster", "Chris Demo", "Robin Test", "Kim Beispiel"])
    }

    @Test @MainActor func keypadAvailabilityRequiresAnActiveUnheldConversation() {
        var call = PreviewFixtures.session(account: UUID(), slot: 0, remote: "101", start: Date())
        #expect(CallPresentation.canSendTones(call))
        call.held = true
        #expect(!CallPresentation.canSendTones(call))
        call.held = false
        call.phase = .ringing
        #expect(!CallPresentation.canSendTones(call))
    }
    #endif
}
