import SwiftUI
import TelefonDomain

struct AddNumberToContact: View {
    private enum Layout {
        static let dialogHorizontalInset: CGFloat = 20
        // The native inset list contributes another 10 pt around its rows.
        static let listOuterInset: CGFloat = 10
    }

    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let number: String
    @State private var search = ""
    @State private var selected: UUID?
    @State private var error: String?
    private var contacts: [PhoneContact] {
        model.snapshot.contacts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.company.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func containsNumber(_ contact: PhoneContact) -> Bool { contact.numbers.contains { ContactFavorites.equivalent($0, number) } }
    private var canSave: Bool {
        guard let contact = model.snapshot.contacts.first(where: { $0.id == selected }) else { return false }
        return contact.numbers.count < 20 && !containsNumber(contact)
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add to Contact").font(.title2.weight(.semibold))
                Text(number).foregroundStyle(.secondary).textSelection(.enabled)
                TextField("Search Contacts", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 4)
            }.padding(.horizontal, Layout.dialogHorizontalInset).padding(.top, 20)
            List(contacts, selection: $selected) { contact in
                HStack(spacing: 10) {
                    ContactAvatar(contact: contact, size: 32)
                    Text(contact.name)
                    Spacer()
                    if containsNumber(contact) { Text("Already Included").font(.caption).foregroundStyle(.secondary) }
                    else if contact.numbers.count >= 20 { Text("20-number limit reached").font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 4).tag(contact.id)
            }.listStyle(.inset)
                .padding(.horizontal, Layout.listOuterInset)
                .overlay { if contacts.isEmpty { ContentUnavailableView("No Contacts", systemImage: "person.crop.circle") } }
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
                    .padding(.horizontal, Layout.dialogHorizontalInset)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    guard let selected else { return }
                    do { try model.addNumber(number, to: selected); dismiss() } catch { self.error = L10n.error(error) }
                }.telefonButtonStyle(.prominent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(Layout.dialogHorizontalInset)
        }.frame(width: 500, height: 500).telefonButtonStyle()
    }
}
