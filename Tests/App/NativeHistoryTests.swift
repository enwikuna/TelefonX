import AppKit
import SwiftUI
import Testing
import TelefonDomain
@testable import TelefonX

@Suite struct NativeHistoryTests {
    @Test func fiveFiltersComposeWithSearchAndIncludeMissedIncoming() {
        var incoming = CallRecord(session: CallSession(handle: .init(slot: 1, generation: 1), accountID: UUID(),
            remote: "101", incoming: true, phase: .ended), accountName: "Test")
        var outgoing = incoming; outgoing.id = UUID(); outgoing.incoming = false; outgoing.remote = "102"; outgoing.outcome = .answered
        var answeredIncoming = incoming; answeredIncoming.id = UUID(); answeredIncoming.remote = "103"; answeredIncoming.outcome = .answered
        incoming.outcome = .missed
        var blocked = incoming; blocked.id = UUID(); blocked.remote = "104"; blocked.outcome = .blocked
        let history = [incoming, outgoing, answeredIncoming, blocked]
        func filtered(_ filter: HistoryFilter, hideBlockedInAll: Bool = false, search: String = "") -> Set<UUID> {
            Set(HistoryPresentation.records(history, filter: filter, hideBlockedInAll: hideBlockedInAll,
                                            search: search, displayName: { $0 == "101" ? "Alex" : $0 }).map(\.id))
        }
        #expect(HistoryFilter.allCases.count == 5)
        #expect(filtered(.all) == Set(history.map(\.id)))
        #expect(filtered(.incoming) == [incoming.id, answeredIncoming.id, blocked.id])
        #expect(filtered(.outgoing) == [outgoing.id])
        #expect(filtered(.missed) == [incoming.id])
        #expect(filtered(.blocked) == [blocked.id])
        #expect(filtered(.all, hideBlockedInAll: true) == [incoming.id, outgoing.id, answeredIncoming.id])
        #expect(filtered(.blocked, hideBlockedInAll: true) == [blocked.id])
        #expect(filtered(.incoming, search: " alex ") == [incoming.id])
        #expect(filtered(.outgoing, search: "alex").isEmpty)
        #expect(PhoneSection.history.rawValue == "Recents")
    }

    @Test func blockingANumberDoesNotRewriteItsEarlierCallHistory() {
        var earlierCall = CallRecord(
            session: CallSession(handle: .init(slot: 1, generation: 1), accountID: UUID(),
                                 remote: "102", incoming: false, phase: .ended),
            accountName: "Home"
        )
        earlierCall.outcome = .answered
        let rules = [BlockRule(number: "102")]

        #expect(Routing.isBlocked(earlierCall.remote, rules: rules, anonymous: false))
        #expect(HistoryPresentation.outcome(earlierCall) == "Outgoing")
        #expect(!HistoryFilter.blocked.includes(earlierCall))
        #expect(HistoryPresentation.records([earlierCall], filter: .all, hideBlockedInAll: true,
                                            search: "", displayName: { $0 }) == [earlierCall])
    }

    @Test func selectedRowHidesBothAdjacentSeparators() {
        for selected in 0..<5 {
            for row in 0..<5 {
                #expect(HistoryPresentation.showsSeparator(after: row, count: 5, selectedRow: selected)
                        == (row < 4 && row != selected && row + 1 != selected))
            }
        }
        #expect(!HistoryPresentation.showsSeparator(after: 0, count: 1, selectedRow: nil))
        #expect(!HistoryPresentation.showsSeparator(after: -1, count: 0, selectedRow: nil))
        #expect(HistoryPresentation.showsSeparator(after: 0, count: 2, selectedRow: nil))
        #expect(!HistoryPresentation.showsSeparator(after: 0, count: 5, selectedRows: [1, 3]))
        #expect(!HistoryPresentation.showsSeparator(after: 1, count: 5, selectedRows: [1, 3]))
        #expect(!HistoryPresentation.showsSeparator(after: 2, count: 5, selectedRows: [1, 3]))
        #expect(HistoryPresentation.showsSeparator(after: 2, count: 6, selectedRows: [1, 4]))
    }

    @Test func bulkRequestsExposeOnlySelectionSizedDeleteCopy() {
        let account = UUID()
        func record(_ slot: Int32) -> CallRecord {
            CallRecord(session: CallSession(handle: .init(slot: slot, generation: 1), accountID: account,
                                            remote: "10\(slot)", incoming: false, phase: .connected),
                       accountName: "Test")
        }
        let history = HistoryActionRequest(deleting: [record(1), record(2)])
        #expect(history.title == "Delete 2 Calls?")
        #expect(history.button == "Delete 2")

        let contacts = ContactActionRequest(deleting: [PhoneContact(name: "Alex"), PhoneContact(name: "Sam")])
        #expect(contacts.title == "Delete 2 Contacts?")
        #expect(contacts.button == "Delete 2")
    }

    @Test @MainActor func selectedRowAndSeparatorsShareAppleListGeometry() {
        #expect(HistoryRowLayout.listContentHorizontalInset == 16)
        #expect(HistoryRowLayout.swiftUISelectionSurfaceHorizontalInset == 8)
        #expect(HistoryRowLayout.nativeSelectionSurfaceHorizontalInset == 0)
        #expect(HistoryRowLayout.selectionHorizontalInset == 0)
        #expect(HistoryRowLayout.contentHorizontalInset == 8)
        #expect(HistoryRowLayout.selectionContentOverhang == 8)
        #expect(HistoryRowLayout.separatorLeadingInset == 54)
        #expect(HistoryRowLayout.separatorTrailingInset == 8)
        let separator = HistoryRowLayout.separatorRect(
            in: CGRect(x: 0, y: 0, width: 504, height: 64),
            pixelHeight: 0.5)
        #expect(separator.minX + HistoryRowLayout.nativeTableHorizontalInset == 62)
        #expect(separator.maxX + HistoryRowLayout.nativeTableHorizontalInset == 504)
        #expect(HistoryRowLayout.selectionVerticalInset == 3)
        #expect(HistoryRowLayout.selectionCornerRadius == 8)
        #expect(ListToolbarTitle.contentAlignmentOffset == 8)
    }

    @Test @MainActor func separatorOverlayPreservesCellSize() {
        let content = Color.clear.frame(width: 504, height: 64)
        let plain = NSHostingView(rootView: content)
        for visible in [false, true] {
            let decorated = NSHostingView(rootView: content.modifier(ListRowSeparator(visible: visible)))
            #expect(decorated.fittingSize == plain.fittingSize)
        }
    }

    @Test @MainActor func nativeSwipeGuttersSurviveRepeatedLayoutAndResize() {
        let scroll = InsetListScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
        scroll.documentView = NSTableView()
        for width: CGFloat in [520, 800, 480, 520] {
            scroll.setFrameSize(NSSize(width: width, height: 400))
            for _ in 0..<3 {
                scroll.tile()
                #expect(scroll.contentView.frame.minX == 8)
                #expect(scroll.contentView.frame.maxX == width - 8)
            }
        }
    }

    @Test func mainColumnsHaveSafeMinimumWidths() {
        #expect(MainSplitViewLayout.sidebarWidth == 220)
        #expect(MainSplitViewLayout.detailWidth == 330)
        #expect(MainSplitViewLayout.minimumContentWidth == 480)
        #expect(MainSplitViewLayout.minimumWindowWidth == 1120)
    }

    @Test @MainActor func historyAndContactsUseClickOnlyTables() {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        var historySelection: Set<UUID> = []
        let history = HistoryTable(model: model, records: model.snapshot.history, now: Date(),
                                   selection: Binding(get: { historySelection }, set: { historySelection = $0 }),
                                   requestAction: { _ in }, editContact: { _ in }, addToContact: { _ in })
        let historyScroll = HistoryTable.makeScrollView(coordinator: history.makeCoordinator())
        #expect(historyScroll.documentView is ClickOnlyTableView)
        #expect((historyScroll.documentView as? NSTableView)?.style == .plain)
        #expect((historyScroll.documentView as? NSTableView)?.gridStyleMask.isEmpty == true)

        var contactSelection: Set<ContactListSelection> = []
        let contacts = ContactTable(model: model, contacts: model.snapshot.contacts, favoritesOnly: false,
                                    selection: Binding(get: { contactSelection }, set: { contactSelection = $0 }),
                                    requestAction: { _ in }, edit: { _ in })
        let contactsScroll = ContactTable.makeScrollView(coordinator: contacts.makeCoordinator())
        #expect(contactsScroll.documentView is ClickOnlyTableView)
        #expect((contactsScroll.documentView as? NSTableView)?.style == .plain)
        #expect((contactsScroll.documentView as? NSTableView)?.gridStyleMask.isEmpty == true)
    }

    #if DEBUG
    @Test @MainActor func nativeSearchSynchronizesQueryPromptAndCancelWithoutFeedback() {
        _ = NSApplication.shared
        var query = "Sam"
        let binding = Binding<String>(get: { query }, set: { query = $0 })
        let search = ListSearchField(text: binding, prompt: "Search Calls", focusRequest: 0)
        let coordinator = search.makeCoordinator()
        let field = ListSearchField.makeField(coordinator: coordinator)
        coordinator.update(field, parent: search)
        #expect(field.stringValue == "Sam" && field.sendsSearchStringImmediately)
        #expect(field.accessibilityIdentifier() == "list-search")
        field.stringValue = "101"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(query == "101")
        coordinator.update(field, parent: search)
        #expect(field.stringValue == "101")
        field.stringValue = ""
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(query.isEmpty)
        let contactsSearch = ListSearchField(text: binding, prompt: "Name or Number", focusRequest: 0)
        coordinator.update(field, parent: contactsSearch)
        #expect(field.placeholderString == "Name or Number")
        #expect(field.stringValue.isEmpty)
        ListSearchField.dismantleNSView(field, coordinator: coordinator)
        #expect(field.delegate == nil)
    }

    @Test @MainActor func tableMaintainsSelectionByIDAndFixedRowsAcrossEmptyFilters() throws {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        PreviewFixtures.apply(.avatars, to: model)
        var selected: Set<UUID> = []
        let binding = Binding<Set<UUID>>(get: { selected }, set: { selected = $0 })
        let now = Date()
        func view(_ records: [CallRecord]) -> HistoryTable {
            HistoryTable(model: model, records: records, now: now, selection: binding, requestAction: { _ in },
                         editContact: { _ in }, addToContact: { _ in })
        }
        let records = model.snapshot.history
        let coordinator = view(records).makeCoordinator()
        let scroll = HistoryTable.makeScrollView(coordinator: coordinator)
        let table = try #require(scroll.documentView as? NSTableView)
        coordinator.update(view(records))
        #expect(table.numberOfRows == records.count)
        #expect(table.rowHeight == 64 && !table.usesAutomaticRowHeights)
        #expect(table.allowsMultipleSelection && table.allowsEmptySelection)
        #expect(table.doubleAction == #selector(HistoryTable.Coordinator.prepareSelectedRecord(_:)))
        model.dialText = ""
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.prepareSelectedRecord(table)
        #expect(model.dialText == (try CallDestination(records[0].remote)).value)
        #expect(model.activeCalls.isEmpty)
        table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        #expect(selected == [records[0].id, records[2].id])
        let reversed = Array(records.reversed())
        coordinator.update(view(reversed))
        #expect(Set(table.selectedRowIndexes.map { reversed[$0].id }) == selected)
        for _ in 0..<5 {
            selected = []
            coordinator.update(view([]))
            #expect(table.numberOfRows == 0 && table.selectedRow == -1)
            coordinator.update(view([records[0]]))
            #expect(table.numberOfRows == 1)
            #expect(table.rect(ofRow: 0).height == 64)
            #expect(coordinator.tableView(table, viewFor: table.tableColumns[0], row: 0) != nil)
        }
        #expect(model.snapshot.history == records)
        HistoryTable.dismantleNSView(scroll, coordinator: coordinator)
        #expect(table.delegate == nil && table.dataSource == nil)
    }

    @Test @MainActor func nativeSwipeActionsAreSafeAndRespectUnknownOrBlockedNumbers() throws {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        PreviewFixtures.apply(.avatars, to: model)
        let records = model.snapshot.history, snapshot = model.snapshot
        let view = HistoryTable(model: model, records: records, now: Date(), selection: .constant([]), requestAction: { _ in },
                                editContact: { _ in }, addToContact: { _ in })
        let coordinator = view.makeCoordinator()
        let scroll = HistoryTable.makeScrollView(coordinator: coordinator)
        let table = try #require(scroll.documentView as? NSTableView)
        let trailing = coordinator.tableView(table, rowActionsForRow: 0, edge: .trailing)
        let leading = coordinator.tableView(table, rowActionsForRow: 0, edge: .leading)
        #expect(trailing.map { $0.image?.accessibilityDescription } == ["Delete …"])
        #expect(leading.map { $0.image?.accessibilityDescription } == ["Block Number …"])
        #expect((trailing + leading).allSatisfy { $0.title.isEmpty && $0.style == .regular && $0.image != nil })
        #expect(coordinator.tableView(table, rowActionsForRow: -1, edge: .trailing).isEmpty)
        let anonymous = try #require(records.firstIndex { $0.remote == "anonymous" })
        #expect(coordinator.tableView(table, rowActionsForRow: anonymous, edge: .trailing).map { $0.image?.accessibilityDescription } == ["Delete …"])
        #expect(coordinator.tableView(table, rowActionsForRow: anonymous, edge: .leading).isEmpty)
        #expect(model.snapshot == snapshot) // Merely exposing actions never writes or calls.
        model.snapshot.blocks = [BlockRule(number: records[0].remote)]
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .trailing).map { $0.image?.accessibilityDescription } == ["Delete …"])
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .leading).map { $0.image?.accessibilityDescription } == ["Unblock …"])
        HistoryTable.dismantleNSView(scroll, coordinator: coordinator)
    }
    #endif
}
