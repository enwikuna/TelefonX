import Foundation
import Testing
import TelefonDomain
@testable import TelefonX

@Suite struct HistoryDisplayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func stamp(_ date: Date, now: Date) -> String {
        HistoryPresentation.timestamp(date, relativeTo: now, calendar: calendar, locale: Locale(identifier: "de_DE"))
    }

    @Test func relativeDatesUseCalendarDaysAndWeekCutoff() {
        let now = date(2026, 9, 4, 15, 0)
        #expect(stamp(date(2026, 9, 4, 9, 5), now: now) == "09:05")
        #expect(stamp(date(2026, 9, 3), now: now) == "Yesterday")
        #expect(stamp(date(2026, 9, 2), now: now) == "Mittwoch")
        #expect(stamp(date(2026, 8, 29), now: now) == "Samstag")
        #expect(stamp(date(2026, 8, 28), now: now) == "28.08.26")
        #expect(stamp(date(2025, 9, 4), now: now) == "04.09.25")
        #expect(stamp(date(2026, 9, 5), now: now) == "05.09.26")
    }

    @Test func midnightAndDaylightSavingDoNotUseFixed24Hours() {
        #expect(stamp(date(2026, 9, 3, 23, 59), now: date(2026, 9, 4, 0, 1)) == "Yesterday")
        #expect(stamp(date(2026, 3, 28, 12), now: date(2026, 3, 29, 12)) == "Yesterday")
        #expect(stamp(date(2026, 10, 24, 12), now: date(2026, 10, 25, 12)) == "Yesterday")
        #expect(stamp(date(2025, 12, 31, 23, 59), now: date(2026, 1, 1, 0, 1)) == "Yesterday")
    }

    @Test func detailKeepsDurationWithoutRepeatingDirection() {
        var call = CallSession(handle: CallHandle(slot: 0, generation: 1), accountID: UUID(), remote: "101", incoming: false, phase: .connected)
        call.answeredAt = Date(); call.endedAt = call.answeredAt?.addingTimeInterval(180)
        var record = CallRecord(session: call, accountName: "Home")
        #expect(HistoryPresentation.detail(record) == "3:00")
        record.incoming = true
        #expect(HistoryPresentation.detail(record) == "3:00")
        record.duration = 3601
        #expect(HistoryPresentation.detail(record) == "1:00:01")
        record.duration = 0
        #expect(HistoryPresentation.detail(record) == "0:00")
        record.outcome = .missed
        #expect(HistoryPresentation.detail(record) == "Missed")
        record.outcome = .failed
        #expect(HistoryPresentation.detail(record) == "Unanswered")
    }

    @Test func historyShowsTheDialedNumberOnlyWhenAContactNameReplacesIt() {
        var call = CallSession(handle: CallHandle(slot: 0, generation: 1), accountID: UUID(),
                               remote: "01731234567", incoming: false, phase: .connected)
        call.answeredAt = Date(); call.endedAt = call.answeredAt?.addingTimeInterval(10)
        let record = CallRecord(session: call, accountName: "Enwikuna")
        #expect(HistoryPresentation.secondaryText(record, displayName: "Johannes Gmelin") == "Enwikuna · 01731234567 · 0:10")
        #expect(HistoryPresentation.secondaryText(record, displayName: "01731234567") == "Enwikuna · 0:10")
    }

    @Test func newContactDraftUsesAResolvedCallerNameButNeverTheNumberAsAName() {
        let resolved = HistoryPresentation.contactDraft(number: "+49374574447100",
                                                        displayName: "Hetzner Online GmbH")
        #expect(resolved.name == "Hetzner Online GmbH")
        #expect(resolved.numbers == ["+49374574447100"])

        let unresolved = HistoryPresentation.contactDraft(number: "+49374574447100",
                                                          displayName: "+49374574447100")
        #expect(unresolved.name.isEmpty)
        #expect(unresolved.numbers == ["+49374574447100"])
    }

    @Test func dialerStartsAtSameInsetInShortAndTallWindows() {
        #expect(IdleDialerLayout.topInset(availableHeight: 400, contentHeight: 500) == 16)
        #expect(IdleDialerLayout.topInset(availableHeight: 720, contentHeight: 500) == 16)
        #expect(IdleDialerLayout.topInset(availableHeight: 1500, contentHeight: 500) == 16)
        #expect(IdleDialerLayout.topInset(availableHeight: 720, contentHeight: 680) == 16)
        #expect(CallWorkspaceLayout.horizontalContentInset == HistoryRowLayout.listContentHorizontalInset)
        #expect(CallWorkspaceLayout.verticalContentInset == 20)
        #expect(LineSelectorLayout.labelLeadingInset == 4)
    }

    @Test func sidebarKeyboardNavigationStaysWithinPrimarySections() {
        #expect(PhoneSection.allCases.count == 4)
        #expect(PhoneSection.history.moved(by: -1) == .history)
        #expect(PhoneSection.history.moved(by: 1) == .reminders)
        #expect(PhoneSection.favorites.moved(by: 1) == .contacts)
        #expect(PhoneSection.contacts.moved(by: 1) == .contacts)
    }

    #if DEBUG
    @Test @MainActor func blockingOnlyTargetsConfirmedNumberAndKeepsContactAndHistory() throws {
        let model = PreviewFixtures.makeModel()
        model.snapshot.contacts = [PhoneContact(name: "Testkontakt", numbers: ["0711 1234567", "0711 7654321"])]
        let contacts = model.snapshot.contacts, history = model.snapshot.history
        #expect(model.snapshot.blocks.isEmpty)
        model.block("0711 1234567")
        #expect(model.snapshot.blocks.count == 1)
        #expect(Routing.isBlocked("+497111234567", rules: model.snapshot.blocks, anonymous: false))
        #expect(!Routing.isBlocked("0711 7654321", rules: model.snapshot.blocks, anonymous: false))
        model.block("+49 711 1234567")
        #expect(model.snapshot.blocks.count == 1)
        model.unblock("+49 711 1234567")
        #expect(model.snapshot.blocks.isEmpty)
        model.block("anonymous")
        #expect(model.snapshot.blocks.isEmpty)
        #expect(model.snapshot.contacts == contacts)
        #expect(model.snapshot.history == history)
    }
    #endif
}
