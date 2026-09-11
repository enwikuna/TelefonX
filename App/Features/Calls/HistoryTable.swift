import AppKit
import SwiftUI
import TelefonDomain

/// Native selection and swipe actions for SwiftUI call rows.
struct HistoryTable: NSViewRepresentable {
    static let rowHeight: CGFloat = 64
    let model: PhoneModel
    let records: [CallRecord]
    let now: Date
    @Binding var selection: Set<UUID>
    let requestAction: (HistoryActionRequest) -> Void
    let editContact: (PhoneContact) -> Void
    let addToContact: (CallRecord) -> Void
    var scheduleReminder: (CallRecord) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(coordinator: context.coordinator)
    }

    static func makeScrollView(coordinator: Coordinator, scroll: NSScrollView = InsetListScrollView()) -> NSScrollView {
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let table = ClickOnlyTableView()
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.rowHeight = Self.rowHeight
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: .init("history"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = coordinator
        table.dataSource = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.prepareSelectedRecord(_:))
        table.setAccessibilityLabel(L10n.text("Recents"))
        table.setAccessibilityIdentifier("history-list")
        scroll.documentView = table
        coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.table?.rowActionsVisible = false
        coordinator.table?.target = nil
        coordinator.table?.doubleAction = nil
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
        coordinator.table = nil
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var parent: HistoryTable
        weak var table: NSTableView?
        private var updating = false
        private var loaded = false
        init(parent: HistoryTable) { self.parent = parent }

        func update(_ next: HistoryTable) {
            guard let table else { return }
            let changed = !loaded || parent.records != next.records
            let clockChanged = parent.now != next.now
            parent = next
            updating = true
            if changed {
                table.rowActionsVisible = false
                table.reloadData()
                loaded = true
            } else if clockChanged {
                // Keep identity and scroll/swipe state; only refresh visible timestamps.
                for row in visibleRows(table) {
                    if let host = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSHostingView<AnyView> {
                        host.rootView = content(for: row)
                    }
                }
            }
            let indices = IndexSet(parent.records.indices.filter { parent.selection.contains(parent.records[$0].id) })
            if table.selectedRowIndexes != indices { table.selectRowIndexes(indices, byExtendingSelection: false) }
            updateRowAppearance(table)
            updating = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.records.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.records.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("history-content")
            let host = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSHostingView<AnyView>)
                ?? NSHostingView(rootView: content(for: row))
            host.identifier = identifier
            host.sizingOptions = []
            host.rootView = content(for: row)
            return host
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            HistoryTableRowView()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { row in
                parent.records.indices.contains(row) ? parent.records[row].id : nil
            })
            if parent.selection != ids { parent.selection = ids }
            updateRowAppearance(table)
        }

        @objc func prepareSelectedRecord(_ sender: NSTableView) {
            guard sender.selectedRowIndexes.count == 1 else { return }
            // ClickOnlyTableView owns selection; AppKit clickedRow can be stale.
            let row = sender.selectedRow
            guard parent.records.indices.contains(row) else { return }
            let record = parent.records[row]
            guard (try? CallDestination(record.remote)) != nil else { return }
            let accountID = parent.model.snapshot.accounts.contains { $0.id == record.accountID }
                ? record.accountID : nil
            parent.model.prepareDial(record.remote, accountID: accountID)
        }

        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard parent.records.indices.contains(row) else { return [] }
            let record = parent.records[row]
            if edge == .trailing {
                return [action(.delete, record: record, symbol: "trash.fill", color: .systemRed)]
            }
            let hasNumber = (try? CallDestination(record.remote)) != nil
            let blocked = Routing.isBlocked(record.remote, rules: parent.model.snapshot.blocks, anonymous: false)
            guard edge == .leading, hasNumber else { return [] }
            return blocked
                ? [action(.unblock, record: record, symbol: "hand.raised.slash.fill", color: .systemBlue)]
                : [action(.block, record: record, symbol: "hand.raised.fill", color: .systemOrange)]
        }

        private func action(_ kind: HistoryActionRequest.Kind, record: CallRecord, symbol: String, color: NSColor) -> NSTableViewRowAction {
            let request = HistoryActionRequest(kind: kind, record: record)
            // Confirm deletion before removal; use the image description for accessibility.
            let action = NSTableViewRowAction(style: .regular, title: "") { [weak self] _, _ in
                guard let self else { return }
                self.table?.rowActionsVisible = false
                self.parent.requestAction(request)
            }
            action.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "\(request.button) …")
            action.backgroundColor = color
            return action
        }

        private func content(for row: Int) -> AnyView {
            let record = parent.records[row]
            let selected = parent.selection.contains(record.id)
            return AnyView(HistoryRow(record: record, now: parent.now, selected: selected,
                                     selectionCount: parent.selection.count,
                                     requestAction: parent.requestAction, editContact: parent.editContact,
                                     addToContact: parent.addToContact,
                                     scheduleReminder: parent.scheduleReminder,
                                     deleteSelection: { [weak self] in
                                         guard let self else { return }
                                         let records = self.parent.records.filter { self.parent.selection.contains($0.id) }
                                         self.parent.requestAction(.init(deleting: records))
                                     })
                .modifier(ListRowSeparator(visible: HistoryPresentation.showsSeparator(
                    after: row, count: parent.records.count, selectedRows: table?.selectedRowIndexes ?? [])))
                .environment(parent.model).id(record.id))
        }

        private func visibleRows(_ table: NSTableView) -> Range<Int> {
            let range = table.rows(in: table.visibleRect)
            guard range.location != NSNotFound else { return 0..<0 }
            return range.location..<min(NSMaxRange(range), parent.records.count)
        }
        private func updateRowAppearance(_ table: NSTableView) {
            for row in visibleRows(table) {
                if let host = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSHostingView<AnyView> {
                    host.rootView = content(for: row)
                }
            }
        }
    }
}
