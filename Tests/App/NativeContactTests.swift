import AppKit
import SwiftUI
import Testing
import TelefonDomain
@testable import TelefonX

@Suite struct NativeContactTests {
    @Test func contactEditorTitlesMatchTheEditingMode() {
        #expect(ContactEditorPresentation.titleKey(isExisting: false) == "Add Contact")
        #expect(ContactEditorPresentation.titleKey(isExisting: true) == "Edit Contact")
    }

    @Test func contactSourceFiltersExposeTheExpectedSources() {
        #expect(ContactSourceFilter.all.includesTelefonX && ContactSourceFilter.all.includesApple)
        #expect(ContactSourceFilter.telefonX.includesTelefonX && !ContactSourceFilter.telefonX.includesApple)
        #expect(!ContactSourceFilter.apple.includesTelefonX && ContactSourceFilter.apple.includesApple)
        let group = ContactSourceFilter.group("Support")
        #expect(group.includesTelefonX && !group.includesApple && group.group == "Support")
    }

    @Test func contactGroupsAreTrimmedDeduplicatedSortedAndMatchedCaseInsensitively() {
        let contacts = [
            PhoneContact(name: "A", numbers: ["101"], group: " Support "),
            PhoneContact(name: "B", numbers: ["102"], group: "support"),
            PhoneContact(name: "C", numbers: ["103"], group: "Büro"),
            PhoneContact(name: "D", numbers: ["104"], group: " ")
        ]
        #expect(ContactGroups.available(in: contacts) == ["Büro", "Support"])
        #expect(ContactGroups.normalized("  Vertrieb\n") == "Vertrieb")
        #expect(ContactGroups.matches(contacts[0], group: "support"))
        #expect(!ContactGroups.matches(contacts[2], group: "Support"))
    }

    @Test func blockStatusDistinguishesNonePartialAndComplete() {
        let contact = PhoneContact(name: "Alex", numbers: ["101", "102"])
        #expect(ContactBlockStatus.resolve(contact, rules: []) == .init(blocked: 0, valid: 2))
        let partial = ContactBlockStatus.resolve(contact, rules: [BlockRule(number: "101")])
        #expect(partial.hasBlockedNumbers && partial.canBlockMore && partial.label == "Partially Blocked")
        let complete = ContactBlockStatus.resolve(contact, rules: [BlockRule(number: "101"), BlockRule(number: "102")])
        #expect(complete.hasBlockedNumbers && !complete.canBlockMore && complete.label == "Blocked")
    }

    @Test @MainActor func blockingAContactAddsEveryValidNumberOnlyOnce() {
        let model = PreviewFixtures.makeModel()
        model.snapshot.blocks = [BlockRule(number: "101")]
        model.block(["101", "102", " "])
        #expect(model.snapshot.blocks.count == 2)
        #expect(Routing.isBlocked("101", rules: model.snapshot.blocks, anonymous: false))
        #expect(Routing.isBlocked("102", rules: model.snapshot.blocks, anonymous: false))
    }

    @Test @MainActor func nativeContactRowsMatchHistorySwipeDirectionsAndStartAtZeroInset() throws {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        let contact = PhoneContact(name: "Alex", numbers: ["101"])
        model.snapshot.contacts = [contact]
        var editedContact: PhoneContact?
        let view = ContactTable(model: model, contacts: [contact], favoritesOnly: false,
                                selection: .constant([]), requestAction: { _ in }, edit: { editedContact = $0 })
        let coordinator = view.makeCoordinator()
        let scroll = ContactTable.makeScrollView(coordinator: coordinator)
        let table = try #require(scroll.documentView as? NSTableView)
        coordinator.update(view)
        #expect(scroll.automaticallyAdjustsContentInsets)
        #expect(!table.floatsGroupRows)
        #expect(table.rowHeight == HistoryTable.rowHeight)
        #expect(table.allowsMultipleSelection && table.allowsEmptySelection)
        #expect(table.doubleAction == #selector(ContactTable.Coordinator.openSelectedContact(_:)))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.openSelectedContact(table)
        #expect(editedContact?.id == contact.id)
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .trailing)
            .map { $0.image?.accessibilityDescription } == ["Delete …"])
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .leading)
            .map { $0.image?.accessibilityDescription } == ["Block Contact …"])
        model.snapshot.blocks = [BlockRule(number: "101")]
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .leading).first?.backgroundColor == .systemBlue)
        #expect(RowActionIcon.frameSize == 28 && RowActionIcon.symbolSize == 16)
        ContactTable.dismantleNSView(scroll, coordinator: coordinator)
    }

    @Test @MainActor func selectedContactHidesAdjacentSeparatorsLikeHistory() throws {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        let contacts = [
            PhoneContact(name: "Alex", numbers: ["101"]),
            PhoneContact(name: "Sam", numbers: ["102"]),
            PhoneContact(name: "Chris", numbers: ["103"])
        ]
        var selection: Set<ContactListSelection> = []
        let view = ContactTable(model: model, contacts: contacts, favoritesOnly: false,
                                selection: Binding(get: { selection }, set: { selection = $0 }),
                                requestAction: { _ in }, edit: { _ in })
        let coordinator = view.makeCoordinator()
        let scroll = ContactTable.makeScrollView(coordinator: coordinator)
        let table = try #require(scroll.documentView as? NSTableView)
        coordinator.update(view)

        #expect(coordinator.showsSeparator(after: 0, in: table))
        #expect(coordinator.showsSeparator(after: 1, in: table))
        #expect(!coordinator.showsSeparator(after: 2, in: table))
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(!coordinator.showsSeparator(after: 0, in: table))
        #expect(!coordinator.showsSeparator(after: 1, in: table))
        ContactTable.dismantleNSView(scroll, coordinator: coordinator)
    }

    @Test @MainActor func staleClickedRowCannotOpenLocalContactForAppleSelection() {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        let local = PhoneContact(name: "Alex", numbers: ["101"])
        let apple = AppleContact(id: "external", name: "Apple", company: "",
                                 phoneNumbers: [ContactPhoneNumber(value: "102", label: .mobile)], photoData: nil)
        var selection: Set<ContactListSelection> = []
        var edited: PhoneContact?
        let binding = Binding(get: { selection }, set: { selection = $0 })
        func view(_ filter: ContactSourceFilter) -> ContactTable {
            ContactTable(model: model, contacts: [local], appleContacts: [apple], separatesSources: true,
                         sourceFilter: filter, favoritesOnly: false, selection: binding,
                         requestAction: { _ in }, edit: { edited = $0 })
        }
        let coordinator = view(.all).makeCoordinator()
        let table = StaleContactClickTable()
        table.dataSource = coordinator
        table.delegate = coordinator
        table.allowsEmptySelection = true
        coordinator.table = table
        coordinator.update(view(.all))
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        coordinator.openSelectedContact(table)
        #expect(edited?.id == local.id)
        edited = nil
        // AppKit still reports the local row after the custom mouse handler selects Apple.
        table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
        coordinator.openSelectedContact(table)
        #expect(edited == nil)
        coordinator.update(view(.apple))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.openSelectedContact(table)
        #expect(edited == nil)
        table.delegate = nil
        table.dataSource = nil
    }

    @Test @MainActor func selectAllStaysWithinSelectedContactSourceAndVisibleRows() throws {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        let locals = [PhoneContact(name: "Alex"), PhoneContact(name: "Sam")]
        let apples = (0..<3).map {
            AppleContact(id: "apple-\($0)", name: "External \($0)", company: "", phoneNumbers: [], photoData: nil)
        }
        var selection: Set<ContactListSelection> = []
        let binding = Binding(get: { selection }, set: { selection = $0 })
        func view(_ external: [AppleContact]) -> ContactTable {
            ContactTable(model: model, contacts: locals, appleContacts: external, separatesSources: true,
                         favoritesOnly: false, selection: binding, requestAction: { _ in }, edit: { _ in })
        }
        let coordinator = view(apples).makeCoordinator()
        let scroll = ContactTable.makeScrollView(coordinator: coordinator)
        let table = try #require(scroll.documentView as? ClickOnlyTableView)
        coordinator.update(view(apples))
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        table.selectAll(nil)
        #expect(selection == Set(locals.map { .local($0.id) }))
        #expect(table.selectedRowIndexes == IndexSet([1, 2]))
        table.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        table.selectAll(nil)
        #expect(selection == Set(apples.map { .apple($0.id) }))
        #expect(table.selectedRowIndexes == IndexSet([4, 5, 6]))
        coordinator.update(view([apples[1]]))
        table.selectAll(nil)
        #expect(selection == [.apple(apples[1].id)])
        table.deselectAll(nil)
        table.selectAll(nil)
        #expect(selection == Set(locals.map { .local($0.id) } + [.apple(apples[1].id)]))
        ContactTable.dismantleNSView(scroll, coordinator: coordinator)
        #expect(table.selectAllInContext == nil)
    }

    @Test @MainActor func appleContactsUseReadOnlyNativeSourceRows() throws {
        _ = NSApplication.shared
        let model = PreviewFixtures.makeModel()
        let local = PhoneContact(name: "Lokal", numbers: ["101"])
        let apple = AppleContact(id: "apple-read-only", name: "Apple", company: "",
                                 phoneNumbers: [ContactPhoneNumber(value: "102", label: .mobile)], photoData: nil)
        var selection: Set<ContactListSelection> = []
        var edited: PhoneContact?
        let view = ContactTable(model: model, contacts: [local], appleContacts: [apple], separatesSources: true,
                                favoritesOnly: false,
                                selection: Binding(get: { selection }, set: { selection = $0 }),
                                requestAction: { _ in }, edit: { edited = $0 })
        let coordinator = view.makeCoordinator()
        let scroll = ContactTable.makeScrollView(coordinator: coordinator)
        let table = try #require(scroll.documentView as? NSTableView)
        coordinator.update(view)
        table.reloadData()

        #expect(coordinator.numberOfRows(in: table) == 4)
        #expect(table.rect(ofRow: 0).height == CenterColumnSectionLayout.height)
        #expect(table.rect(ofRow: 2).height == CenterColumnSectionLayout.height
                + CenterColumnSectionLayout.interSectionSpacing)
        #expect(!coordinator.tableView(table, shouldSelectRow: 0))
        #expect(coordinator.tableView(table, shouldSelectRow: 1))
        #expect(coordinator.tableView(table, rowActionsForRow: 3, edge: .leading).isEmpty)
        #expect(coordinator.tableView(table, rowActionsForRow: 3, edge: .trailing).isEmpty)

        table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
        coordinator.openSelectedContact(table)
        #expect(edited == nil)

        let telefonXOnly = ContactTable(model: model, contacts: [local], appleContacts: [apple],
                                        separatesSources: true, sourceFilter: .telefonX,
                                        favoritesOnly: false, selection: .constant([]),
                                        requestAction: { _ in }, edit: { _ in })
        #expect(telefonXOnly.makeCoordinator().numberOfRows(in: table) == 1)
        let appleOnly = ContactTable(model: model, contacts: [local], appleContacts: [apple],
                                    separatesSources: true, sourceFilter: .apple,
                                    favoritesOnly: false, selection: .constant([]),
                                    requestAction: { _ in }, edit: { _ in })
        #expect(appleOnly.makeCoordinator().numberOfRows(in: table) == 1)
        let favorites = ContactTable(model: model, contacts: [local], appleContacts: [apple],
                                     separatesSources: true, sourceFilter: .all,
                                     favoritesOnly: true, selection: .constant([]),
                                     requestAction: { _ in }, edit: { _ in })
        #expect(favorites.makeCoordinator().numberOfRows(in: table) == 1)
        let noAppleContacts = ContactTable(model: model, contacts: [local], appleContacts: [],
                                           separatesSources: true, sourceFilter: .all,
                                           favoritesOnly: false, selection: .constant([]),
                                           requestAction: { _ in }, edit: { _ in })
        #expect(noAppleContacts.makeCoordinator().numberOfRows(in: table) == 2)
        ContactTable.dismantleNSView(scroll, coordinator: coordinator)
    }
}

@MainActor private final class StaleContactClickTable: NSTableView {
    override var clickedRow: Int { 1 }
}
