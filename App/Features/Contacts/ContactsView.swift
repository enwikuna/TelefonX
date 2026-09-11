import SwiftUI
import TelefonDomain

struct ContactsView: View {
    @Environment(PhoneModel.self) private var model
    @Binding var searchState: ListSearchState
    private var search: String { searchState.text }
    let favoritesOnly: Bool
    @State private var editing: PhoneContact?
    @State private var selectedContacts: Set<ContactListSelection> = []
    @State private var actionRequest: ContactActionRequest?
    @State private var sourceFilter: ContactSourceFilter = .all
    private var appleSourceAvailable: Bool {
        !favoritesOnly && model.appleContactsEnabled && model.appleContactsAuthorization == .authorized
    }
    private var groups: [String] { ContactGroups.available(in: model.snapshot.contacts) }
    private var filterAvailable: Bool { appleSourceAvailable || !groups.isEmpty }
    private var effectiveSourceFilter: ContactSourceFilter {
        switch sourceFilter {
        case .apple where !appleSourceAvailable: .all
        case .group(let group) where !ContactGroups.contains(group, in: groups): .all
        default: sourceFilter
        }
    }
    private var localContacts: [PhoneContact] {
        guard effectiveSourceFilter.includesTelefonX else { return [] }
        let source = favoritesOnly ? ContactFavorites.ordered(model.snapshot.contacts)
            : model.snapshot.contacts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return source.filter { contact in
            let belongsToGroup = effectiveSourceFilter.group.map { ContactGroups.matches(contact, group: $0) } ?? true
            return belongsToGroup && (search.isEmpty || [contact.name, contact.company, contact.group, contact.numbers.joined()]
                .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    private var appleContacts: [AppleContact] {
        guard appleSourceAvailable, effectiveSourceFilter.includesApple else { return [] }
        return model.visibleAppleContacts.filter {
            search.isEmpty || [$0.name, $0.company, $0.numbers.joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    private var hasSearchableContacts: Bool {
        if favoritesOnly { return model.snapshot.contacts.contains(where: \.favorite) }
        return !model.snapshot.contacts.isEmpty || (appleSourceAvailable && !model.visibleAppleContacts.isEmpty)
    }
    private var contactCount: Int { localContacts.count + appleContacts.count }
    var body: some View {
        VStack(spacing: 0) {
            if contactCount == 0 {
                ContentUnavailableView(search.isEmpty ? (favoritesOnly ? "Your Favorites" : "Internal Address Book") : "No Contacts Found",
                                       systemImage: favoritesOnly ? "star" : "person.crop.rectangle",
                                       description: Text(search.isEmpty ? (favoritesOnly ? "Mark contacts as favorites in the address book." : "Your contacts stay on this Mac. Add a contact or import your address book.") : "Try another contact name or number."))
                    .windowCenteredEmptyState()
            } else {
                ContactTable(model: model, contacts: localContacts, appleContacts: appleContacts,
                             separatesSources: appleSourceAvailable, sourceFilter: effectiveSourceFilter,
                             favoritesOnly: favoritesOnly,
                             selection: $selectedContacts, requestAction: { actionRequest = $0 },
                             edit: { editing = $0 })
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .navigationSubtitle(countText)
        // Empty windows have no scrolling content beneath the toolbar.
        .toolbarBackgroundVisibility(contactCount == 0 && model.snapshot.accounts.isEmpty ? .hidden : .automatic,
                                     for: .windowToolbar)
        .listToolbar(favoritesOnly ? "Favorites" : "Contacts", subtitle: countText,
                     state: $searchState, prompt: "Name or Number", showsSearch: hasSearchableContacts,
                     retainsActions: !favoritesOnly) {
            if !favoritesOnly {
                if hasSearchableContacts && filterAvailable {
                    ToolbarItem(id: "contacts-source-filter", placement: .primaryAction) {
                        ContactSourceFilterMenu(selection: $sourceFilter,
                                                appleAvailable: appleSourceAvailable,
                                                groups: groups)
                    }
                }
                ToolbarItem(id: "contacts-import", placement: .primaryAction) {
                    Menu {
                        Button("Import CSV …", systemImage: "tablecells") { FileActions.importCSV(model) }
                            .disabled(!contactTransferUnlocked)
                        Button("Export CSV …", systemImage: "square.and.arrow.up") { FileActions.exportCSV(model) }
                            .disabled(!contactTransferUnlocked || model.snapshot.contacts.isEmpty)
                        if !contactTransferUnlocked {
                            Divider()
                            ProAccessButton()
                        }
                    } label: { Label("Import Contacts", systemImage: "square.and.arrow.down").labelStyle(.iconOnly) }
                    .menuIndicator(.hidden).help("Import or Export Contacts").accessibilityIdentifier("contacts-import")
                }
                ToolbarItem(id: "contacts-add", placement: .primaryAction) {
                    Button { editing = PhoneContact() } label: { Label("Add Contact …", systemImage: "plus").labelStyle(.iconOnly) }
                        .help("Add Contact …").keyboardShortcut("n", modifiers: [.command, .shift])
                        .accessibilityIdentifier("contacts-add")
                }
            }
        }
        .sheet(item: $editing) { ContactEditor(contact: $0).environment(model) }
        .task { if !favoritesOnly { await model.refreshAppleContacts() } }
        .onChange(of: appleSourceAvailable) { _, available in
            if !available && sourceFilter == .apple { sourceFilter = .all }
        }
        .onChange(of: groups) { _, availableGroups in
            if let selectedGroup = sourceFilter.group,
               !ContactGroups.contains(selectedGroup, in: availableGroups) {
                sourceFilter = .all
            }
        }
        .onChange(of: localContacts.map { ContactListSelection.local($0.id) }
                  + appleContacts.map { ContactListSelection.apple($0.id) }) { _, ids in
            selectedContacts.formIntersection(ids)
        }
        .alert(actionRequest?.title ?? "Contacts",
               isPresented: Binding(get: { actionRequest != nil }, set: { if !$0 { actionRequest = nil } }),
               presenting: actionRequest) { request in
            Button("Cancel", role: .cancel) { }
            Button(request.button, role: .destructive) {
                switch request.kind {
                case .block: model.block(request.contacts.flatMap(\.numbers))
                case .delete:
                    do { try model.deleteContacts(Set(request.contacts.map(\.id))) }
                    catch { model.report(error) }
                }
            }
        } message: { request in Text(request.message) }
    }

    private var countText: String {
        if favoritesOnly { return L10n.format("%lld Favorites", Int64(contactCount)) }
        return L10n.format(contactCount == 1 ? "%lld Contact" : "%lld Contacts", Int64(contactCount))
    }

    private var contactTransferUnlocked: Bool {
        model.purchases.access.permits(.contactImportExport)
    }

}
