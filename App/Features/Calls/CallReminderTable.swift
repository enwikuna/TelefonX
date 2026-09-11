import AppKit
import SwiftUI
import TelefonDomain

struct CallReminderTableSection: Equatable {
    let title: String
    let reminders: [CallReminder]
}

/// Native multi-selection with the same neutral row presentation as recents.
struct CallReminderTable: NSViewRepresentable {
    let sections: [CallReminderTableSection]
    @Binding var selection: Set<UUID>
    let content: (CallReminder, Bool) -> AnyView
    let edit: (CallReminder) -> Void
    let delete: (Set<UUID>) -> Void
    let complete: (Set<UUID>) -> Void

    enum Entry: Equatable {
        case header(String, Bool)
        case reminder(CallReminder)
        var reminder: CallReminder? {
            if case .reminder(let value) = self { return value }
            return nil
        }
    }

    var entries: [Entry] {
        sections.filter { !$0.reminders.isEmpty }.enumerated().flatMap { index, section in
            [.header(section.title, index > 0)] + section.reminders.map(Entry.reminder)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView { Self.makeScrollView(coordinator: context.coordinator) }

    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = InsetListScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let table = ClickOnlyTableView()
        table.gridStyleMask = []
        table.selectAllInContext = { [weak coordinator] row in
            coordinator?.selectAllInSection(referenceRow: row)
        }
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.usesAutomaticRowHeights = false
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: .init("reminder"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = coordinator
        table.dataSource = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.editSelected(_:))
        table.setAccessibilityIdentifier("call-reminder-list")
        table.setAccessibilityLabel(L10n.text("Call Reminders"))
        scroll.documentView = table
        coordinator.table = table
        coordinator.update(coordinator.parent)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        (coordinator.table as? ClickOnlyTableView)?.selectAllInContext = nil
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
        coordinator.table?.target = nil
        coordinator.table?.doubleAction = nil
        coordinator.table = nil
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: CallReminderTable
        var entries: [Entry] = []
        weak var table: NSTableView?
        private var updating = false
        init(_ parent: CallReminderTable) { self.parent = parent }

        func update(_ next: CallReminderTable) {
            guard let table else { return }
            let nextEntries = next.entries
            let changed = entries != nextEntries
            parent = next
            updating = true
            entries = nextEntries
            if changed { table.reloadData() }
            let indexes = IndexSet(entries.indices.filter { index in
                entries[index].reminder.map { parent.selection.contains($0.id) } ?? false
            })
            if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
            refreshRows()
            updating = false
        }
        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard entries.indices.contains(row) else { return HistoryTable.rowHeight }
            if case .header(_, let gap) = entries[row] {
                return CenterColumnSectionLayout.height + (gap ? CenterColumnSectionLayout.interSectionSpacing : 0)
            }
            return HistoryTable.rowHeight
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { entries.indices.contains(row) && entries[row].reminder != nil }
        func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
            IndexSet(proposed.filter { entries.indices.contains($0) && entries[$0].reminder != nil })
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard entries.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("reminder-content")
            let host = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSHostingView<AnyView>)
                ?? NSHostingView(rootView: rowContent(row))
            host.identifier = identifier
            host.sizingOptions = []
            host.rootView = rowContent(row)
            return host
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            HistoryTableRowView()
        }
        func selectAllInSection(referenceRow: Int) {
            guard let table else { return }
            var range = entries.startIndex..<entries.endIndex
            if entries.indices.contains(referenceRow), entries[referenceRow].reminder != nil {
                let start = entries[..<referenceRow].lastIndex { $0.reminder == nil }.map { $0 + 1 } ?? 0
                let end = entries[(referenceRow + 1)...].firstIndex { $0.reminder == nil } ?? entries.endIndex
                range = start..<end
            }
            let indices = IndexSet(range.filter { entries[$0].reminder != nil })
            table.selectRowIndexes(indices, byExtendingSelection: false)
            parent.selection = Set(indices.compactMap { entries[$0].reminder?.id })
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            parent.selection = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].reminder?.id : nil })
            refreshRows()
        }
        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int,
                       edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard entries.indices.contains(row), let reminder = entries[row].reminder else { return [] }
            let visible = entries.compactMap(\.reminder)
            let ids = CallReminderSelection.contextTargets(clicked: reminder.id, selected: parent.selection,
                                                           visible: Set(visible.map(\.id)))
            let completing = edge == .leading
            let targets = completing
                ? Set(visible.filter { ids.contains($0.id) && $0.completedAt == nil }.map(\.id))
                : ids
            guard !targets.isEmpty else { return [] }
            let label: String
            if completing {
                label = targets.count == 1 ? L10n.text("Mark as Done")
                    : L10n.format("Mark %lld Callbacks as Done", Int64(targets.count))
            } else {
                label = targets.count == 1 ? L10n.text("Delete …")
                    : L10n.format("Delete %lld Callbacks …", Int64(targets.count))
            }
            // Match recents: compact native actions, with deletion confirmed by the view.
            let action = NSTableViewRowAction(style: .regular, title: "") { [weak self] _, _ in
                guard let self else { return }
                self.table?.rowActionsVisible = false
                if completing { self.parent.complete(targets) }
                else { self.parent.delete(targets) }
            }
            action.image = NSImage(systemSymbolName: completing ? "checkmark.circle.fill" : "trash.fill",
                                   accessibilityDescription: label)
            action.backgroundColor = completing ? .systemGreen : .systemRed
            return [action]
        }

        @objc func editSelected(_ table: NSTableView) {
            guard table.selectedRowIndexes.count == 1, entries.indices.contains(table.selectedRow),
                  let reminder = entries[table.selectedRow].reminder else { return }
            parent.edit(reminder)
        }
        private func rowContent(_ row: Int) -> AnyView {
            switch entries[row] {
            case .header(let title, _):
                return AnyView(Text(L10n.text(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, HistoryRowLayout.contentHorizontalInset)
                    .padding(.bottom, CenterColumnSectionLayout.titleBottomInset))
            case .reminder(let reminder):
                return AnyView(parent.content(reminder, table?.selectedRowIndexes.contains(row) == true)
                    .modifier(ListRowSeparator(visible: showsSeparator(row))))
            }
        }
        private func showsSeparator(_ row: Int) -> Bool {
            guard entries.indices.contains(row), entries.indices.contains(row + 1), entries[row].reminder != nil,
                  entries[row + 1].reminder != nil else { return false }
            return table?.selectedRowIndexes.contains(row) != true && table?.selectedRowIndexes.contains(row + 1) != true
        }
        private func refreshRows() {
            guard let table else { return }
            table.enumerateAvailableRowViews { _, row in
                guard self.entries.indices.contains(row) else { return }
                if let host = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSHostingView<AnyView> {
                    host.rootView = self.rowContent(row)
                }
            }
        }
    }
}
