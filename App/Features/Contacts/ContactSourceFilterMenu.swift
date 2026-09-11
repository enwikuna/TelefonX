import SwiftUI
import TelefonDomain

enum ContactSourceFilter: Hashable, Identifiable {
    case all
    case telefonX
    case apple
    case group(String)

    var id: String {
        switch self {
        case .all: "all"
        case .telefonX: "telefonX"
        case .apple: "apple"
        case .group(let name): "group:\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))"
        }
    }
    var title: String {
        switch self {
        case .all: L10n.text("All")
        case .telefonX: L10n.text("TelefonX")
        case .apple: L10n.text("Apple Contacts")
        case .group(let name): name
        }
    }
    var includesTelefonX: Bool { self != .apple }
    var includesApple: Bool { self == .all || self == .apple }
    var group: String? {
        if case .group(let name) = self { name } else { nil }
    }

    var symbol: String {
        switch self {
        case .all: "rectangle.stack"
        case .telefonX: "phone"
        case .apple: "person.crop.rectangle"
        case .group: "person.2"
        }
    }
}

struct ContactSourceFilterMenu: View {
    @Binding var selection: ContactSourceFilter
    let appleAvailable: Bool
    let groups: [String]

    var body: some View {
        Menu {
            Picker("Filter Contacts", selection: $selection) {
                ForEach(sourceFilters) { filter in
                    Label(filter.title, systemImage: filter.symbol).tag(filter)
                }
                if !groups.isEmpty {
                    Divider()
                    ForEach(groups, id: \.self) { group in
                        Label(group, systemImage: "person.2").tag(ContactSourceFilter.group(group))
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Filter Contacts", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.visible)
        .help("\(L10n.text("Filter Contacts")) · \(selection.title)")
        .accessibilityLabel("Filter Contacts")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("contacts-source-filter")
    }

    private var sourceFilters: [ContactSourceFilter] {
        appleAvailable ? [.all, .telefonX, .apple] : [.all, .telefonX]
    }
}

enum ContactGroups {
    static func available(in contacts: [PhoneContact]) -> [String] {
        var namesByIdentity: [String: String] = [:]
        for contact in contacts {
            let name = normalized(contact.group)
            guard !name.isEmpty else { continue }
            let identity = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            namesByIdentity[identity] = namesByIdentity[identity] ?? name
        }
        return namesByIdentity.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func matches(_ contact: PhoneContact, group: String) -> Bool {
        matches(contact.group, group)
    }

    static func contains(_ group: String, in groups: [String]) -> Bool {
        groups.contains { matches($0, group) }
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs)
            .compare(normalized(rhs),
                     options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    static func normalized(_ group: String) -> String {
        group.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
