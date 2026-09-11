import AppKit
import SwiftUI
import TelefonDomain

enum ContactListSelection: Hashable {
    case local(UUID)
    case apple(String)
}

private enum ContactSource: Hashable {
    case telefonX
    case apple

    var title: String { L10n.text(self == .telefonX ? "TelefonX" : "Apple Contacts") }
}

private enum ContactTableEntry: Equatable {
    case section(ContactSource, count: Int)
    case local(PhoneContact)
    case apple(AppleContact)

    var selection: ContactListSelection? {
        switch self {
        case .section: nil
        case .local(let contact): .local(contact.id)
        case .apple(let contact): .apple(contact.id)
        }
    }

    var source: ContactSource? {
        switch self {
        case .section: nil
        case .local: .telefonX
        case .apple: .apple
        }
    }

    var isSection: Bool {
        if case .section = self { true } else { false }
    }
}

/// Native selection and trackpad actions for local contacts, with read-only
/// Apple Contacts presented as a distinct source in the same scrolling table.
struct ContactTable: NSViewRepresentable {
    static let rowHeight: CGFloat = 64
    static let sectionHeight = CenterColumnSectionLayout.height
    let model: PhoneModel
    let contacts: [PhoneContact]
    var appleContacts: [AppleContact] = []
    var separatesSources = false
    var sourceFilter: ContactSourceFilter = .all
    let favoritesOnly: Bool
    @Binding var selection: Set<ContactListSelection>
    let requestAction: (ContactActionRequest) -> Void
    let edit: (PhoneContact) -> Void

    private var entries: [ContactTableEntry] {
        guard separatesSources, !favoritesOnly else { return contacts.map(ContactTableEntry.local) }
        let showsSourceHeaders = sourceFilter == .all
        let localEntries: [ContactTableEntry] = sourceFilter.includesTelefonX && !contacts.isEmpty
            ? (showsSourceHeaders ? [.section(.telefonX, count: contacts.count)] : [])
                + contacts.map(ContactTableEntry.local)
            : []
        let appleEntries: [ContactTableEntry] = sourceFilter.includesApple && !appleContacts.isEmpty
            ? (showsSourceHeaders ? [.section(.apple, count: appleContacts.count)] : [])
                + appleContacts.map(ContactTableEntry.apple)
            : []
        return localEntries + appleEntries
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView { Self.makeScrollView(coordinator: context.coordinator) }

    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = InsetListScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        let table = ClickOnlyTableView()
        table.selectAllInContext = { [weak coordinator] row in
            coordinator?.selectAllInSource(referenceRow: row)
        }
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.usesAutomaticRowHeights = false
        table.floatsGroupRows = false
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.allowsMultipleSelection = !coordinator.parent.favoritesOnly
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: .init("contacts"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = coordinator
        table.dataSource = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.openSelectedContact(_:))
        table.setAccessibilityLabel(L10n.text("Contacts"))
        table.setAccessibilityIdentifier("contacts-list")
        scroll.documentView = table
        coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.table?.rowActionsVisible = false
        (coordinator.table as? ClickOnlyTableView)?.selectAllInContext = nil
        coordinator.table?.target = nil
        coordinator.table?.doubleAction = nil
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
        coordinator.table = nil
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var parent: ContactTable
        weak var table: NSTableView?
        private var updating = false
        private var loaded = false
        private var renderedBlocks: [BlockRule] = []
        init(parent: ContactTable) { self.parent = parent }

        func update(_ next: ContactTable) {
            guard let table else { return }
            let changed = !loaded || parent.entries != next.entries || parent.favoritesOnly != next.favoritesOnly
            let blocksChanged = renderedBlocks != next.model.snapshot.blocks
            parent = next
            updating = true
            if changed {
                table.rowActionsVisible = false
                table.reloadData()
                loaded = true
            } else if blocksChanged {
                reloadVisibleRows(table)
            }
            renderedBlocks = next.model.snapshot.blocks
            let entries = parent.entries
            let indices = IndexSet(entries.indices.filter { entries[$0].selection.map(parent.selection.contains) == true })
            if table.selectedRowIndexes != indices { table.selectRowIndexes(indices, byExtendingSelection: false) }
            reloadVisibleRows(table)
            updating = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.entries.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.entries.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("contact-content")
            let host = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSHostingView<AnyView>)
                ?? NSHostingView(rootView: content(for: row))
            host.identifier = identifier
            host.sizingOptions = []
            host.rootView = content(for: row)
            return host
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            ContactTableRowView()
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard parent.entries.indices.contains(row) else { return ContactTable.rowHeight }
            guard parent.entries[row].isSection else { return ContactTable.rowHeight }
            let precedesAnotherSection = row > 0
            return ContactTable.sectionHeight
                + (precedesAnotherSection ? CenterColumnSectionLayout.interSectionSpacing : 0)
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            parent.entries.indices.contains(row) && !parent.entries[row].isSection
        }

        func selectAllInSource(referenceRow: Int) {
            guard let table, table.allowsMultipleSelection else { return }
            let entries = parent.entries
            let source = entries.indices.contains(referenceRow)
                ? entries[referenceRow].source : nil
            let indices = IndexSet(entries.indices.filter {
                !entries[$0].isSection && (source == nil || entries[$0].source == source)
            })
            table.selectRowIndexes(indices, byExtendingSelection: false)
            // A filtered table may already have exactly these row indexes, so AppKit
            // need not emit a selection notification. Still discard hidden IDs.
            parent.selection = Set(indices.compactMap { entries[$0].selection })
        }

        func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
            IndexSet(proposed.filter { parent.entries.indices.contains($0) && !parent.entries[$0].isSection })
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            let entries = parent.entries
            parent.selection = Set(table.selectedRowIndexes.compactMap { row in
                entries.indices.contains(row) ? entries[row].selection : nil
            })
            reloadVisibleRows(table)
        }

        @objc func openSelectedContact(_ sender: NSTableView) {
            guard !parent.favoritesOnly, sender.selectedRowIndexes.count == 1 else { return }
            // ClickOnlyTableView owns selection; AppKit clickedRow can be stale.
            let row = sender.selectedRow
            guard parent.entries.indices.contains(row), case .local(let contact) = parent.entries[row] else { return }
            parent.edit(contact)
        }

        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int,
                       edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard !parent.favoritesOnly, parent.entries.indices.contains(row),
                  case .local(let contact) = parent.entries[row] else { return [] }
            if edge == .trailing {
                return [action(.delete, contact: contact, symbol: "trash.fill", color: .systemRed)]
            }
            let status = ContactBlockStatus.resolve(contact, rules: parent.model.snapshot.blocks)
            guard edge == .leading else { return [] }
            if status.hasBlockedNumbers {
                let action = NSTableViewRowAction(style: .regular, title: "") { [weak self] _, _ in
                    guard let self else { return }
                    self.table?.rowActionsVisible = false
                    self.parent.model.unblock(contact.numbers)
                }
                action.image = NSImage(systemSymbolName: "hand.raised.slash.fill",
                                       accessibilityDescription: L10n.text("Unblock"))
                action.backgroundColor = .systemBlue
                return [action]
            }
            guard status.canBlockMore else { return [] }
            return [action(.block, contact: contact, symbol: "hand.raised.fill", color: .systemOrange)]
        }

        private func action(_ kind: ContactActionRequest.Kind, contact: PhoneContact,
                            symbol: String, color: NSColor) -> NSTableViewRowAction {
            let request = ContactActionRequest(kind: kind, contact: contact)
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
            guard parent.entries.indices.contains(row) else { return AnyView(EmptyView()) }
            switch parent.entries[row] {
            case .section(let source, let count):
                return AnyView(ContactSourceHeader(title: source.title, count: count))
            case .local(let contact):
                let id = ContactListSelection.local(contact.id)
                let selected = parent.selection.contains(id)
                let selectedLocal = parent.contacts.filter { parent.selection.contains(.local($0.id)) }
                let canModifySelection = selectedLocal.count == parent.selection.count && selectedLocal.count > 1
                return AnyView(ContactRow(contact: contact, favoritesOnly: parent.favoritesOnly,
                                          selected: selected, selectionCount: parent.selection.count,
                                          requestAction: parent.requestAction,
                                          edit: { [weak self] in self?.parent.edit(contact) },
                                          selectedLocalContacts: canModifySelection ? selectedLocal : [])
                    .modifier(ListRowSeparator(visible: table.map { showsSeparator(after: row, in: $0) } ?? false))
                    .environment(parent.model).id(id))
            case .apple(let contact):
                let id = ContactListSelection.apple(contact.id)
                return AnyView(AppleContactRow(contact: contact, selected: parent.selection.contains(id),
                                               selectionCount: parent.selection.count,
                                               copyToLocal: { [weak self] in self?.parent.edit(contact.localCopy()) })
                    .modifier(ListRowSeparator(visible: table.map { showsSeparator(after: row, in: $0) } ?? false))
                    .environment(parent.model).id(id))
            }
        }

        private func visibleRows(_ table: NSTableView) -> Range<Int> {
            let range = table.rows(in: table.visibleRect)
            guard range.location != NSNotFound else { return 0..<0 }
            return range.location..<min(NSMaxRange(range), parent.entries.count)
        }

        private func reloadVisibleRows(_ table: NSTableView) {
            for row in visibleRows(table) {
                if let host = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSHostingView<AnyView> {
                    host.rootView = content(for: row)
                }
            }
        }

        func showsSeparator(after row: Int, in table: NSTableView) -> Bool {
            let entries = parent.entries
            guard entries.indices.contains(row), !entries[row].isSection,
                  entries.indices.contains(row + 1), !entries[row + 1].isSection else { return false }
            return !table.selectedRowIndexes.contains(row)
                && !table.selectedRowIndexes.contains(row + 1)
        }
    }
}
