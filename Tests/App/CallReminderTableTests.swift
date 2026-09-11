import AppKit
import SwiftUI
import Testing
import TelefonDomain
@testable import TelefonX

@Suite @MainActor struct CallReminderTableTests {
    @Test func contextMenuUsesOnlyTheIntendedVisibleSelection() {
        let first = UUID(), second = UUID(), hidden = UUID(), unselected = UUID()
        let selected: Set<UUID> = [first, second, hidden]
        let visible: Set<UUID> = [first, second, unselected]
        #expect(CallReminderSelection.contextTargets(clicked: first, selected: selected, visible: visible) == [first, second])
        #expect(CallReminderSelection.contextTargets(clicked: unselected, selected: selected, visible: visible) == [unselected])
        #expect(CallReminderSelection.contextTargets(clicked: hidden, selected: selected, visible: visible).isEmpty)
    }

    @Test func swipeActionsMatchRecentsEdgesAndSkipCompletedRemindersAndHeaders() {
        _ = NSApplication.shared
        let pending = CallReminder(name: "Pending", number: "101", dueAt: Date())
        var done = CallReminder(name: "Done", number: "102", dueAt: Date())
        done.completedAt = Date()
        let view = CallReminderTable(sections: [.init(title: "Today", reminders: [pending, done])],
                                     selection: .constant([]), content: { _, _ in AnyView(EmptyView()) },
                                     edit: { _ in }, delete: { _ in }, complete: { _ in })
        let coordinator = view.makeCoordinator()
        let scroll = CallReminderTable.makeScrollView(coordinator: coordinator)
        let table = scroll.documentView as! NSTableView
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .trailing).isEmpty)
        #expect(coordinator.tableView(table, rowActionsForRow: -1, edge: .leading).isEmpty)
        #expect(coordinator.tableView(table, rowActionsForRow: 1, edge: .trailing).first?.backgroundColor == .systemRed)
        #expect(coordinator.tableView(table, rowActionsForRow: 1, edge: .leading).first?.backgroundColor == .systemGreen)
        #expect(coordinator.tableView(table, rowActionsForRow: 2, edge: .leading).isEmpty)
        #expect(coordinator.tableView(table, rowActionsForRow: 2, edge: .trailing).count == 1)
        CallReminderTable.dismantleNSView(scroll, coordinator: coordinator)
    }

    @Test func nativeSelectionExcludesHeadersAndRetainsIDsAfterFiltering() {
        _ = NSApplication.shared
        let first = CallReminder(name: "First", number: "101", dueAt: Date())
        let second = CallReminder(name: "Second", number: "102", dueAt: Date())
        let third = CallReminder(name: "Third", number: "103", dueAt: Date())
        var selection: Set<UUID> = []
        let binding = Binding(get: { selection }, set: { selection = $0 })
        func view(_ sections: [CallReminderTableSection]) -> CallReminderTable {
            CallReminderTable(sections: sections, selection: binding,
                              content: { reminder, _ in AnyView(Text(reminder.name)) }, edit: { _ in }, delete: { _ in }, complete: { _ in })
        }
        let initial = view([.init(title: "Today", reminders: [first, second]),
                            .init(title: "Done", reminders: [third])])
        let coordinator = initial.makeCoordinator()
        let scroll = CallReminderTable.makeScrollView(coordinator: coordinator)
        let table = scroll.documentView as! NSTableView
        table.selectAll(nil)
        #expect(table.selectedRowIndexes == IndexSet([1, 2, 4]))
        #expect(selection == [first.id, second.id, third.id])
        #expect(table.gridStyleMask.isEmpty)
        #expect(coordinator.tableView(table, rowViewForRow: 1) is HistoryTableRowView)

        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        table.selectAll(nil)
        #expect(selection == [first.id, second.id])
        table.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        table.selectAll(nil)
        #expect(selection == [third.id])
        table.deselectAll(nil)
        table.selectAll(nil)
        #expect(selection == [first.id, second.id, third.id])
        table.deselectRow(2)
        #expect(selection == [first.id, third.id])
        coordinator.update(view([.init(title: "Done", reminders: [third])]))
        #expect(table.selectedRowIndexes == IndexSet(integer: 1))
        #expect(!coordinator.tableView(table, shouldSelectRow: 0))
        CallReminderTable.dismantleNSView(scroll, coordinator: coordinator)
        #expect(table.delegate == nil)
        #expect(table.dataSource == nil)
    }
}
