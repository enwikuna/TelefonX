import SwiftUI
import TelefonDomain

struct ContactEditor: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var contact: PhoneContact
    @State private var phoneNumbers: [EditablePhoneNumber]
    @State private var error: String?
    @State private var importingPhoto = false
    init(contact: PhoneContact) {
        _contact = State(initialValue: contact)
        let existing = contact.phoneNumbers.map(EditablePhoneNumber.init)
        _phoneNumbers = State(initialValue: existing.isEmpty ? [EditablePhoneNumber(label: .mobile)] : existing)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editorTitle).font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(22)
            ContactPhotoPicker(contact: $contact, importing: $importingPhoto)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)
            Form {
                TextField("Name", text: $contact.name)
                TextField("Company", text: $contact.company)
                TextField("Email", text: $contact.email)
                LabeledContent("Group") {
                    GroupSuggestionField(text: $contact.group,
                                         suggestions: ContactGroups.available(in: model.snapshot.contacts))
                }
                Section("Phone Numbers") {
                    ForEach($phoneNumbers) { $phoneNumber in
                        HStack(spacing: 10) {
                            Picker("Type", selection: $phoneNumber.label) {
                                ForEach(ContactPhoneLabel.allCases, id: \.self) { label in Text(label.title).tag(label) }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                            TextField("", text: $phoneNumber.value)
                                .textContentType(.telephoneNumber)
                                .accessibilityLabel("Phone Number")
                            Button {
                                removePhoneNumber(phoneNumber.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Remove Phone Number")
                            .accessibilityLabel("Remove Phone Number")
                        }
                    }
                    Button {
                        phoneNumbers.append(EditablePhoneNumber(label: .mobile))
                    } label: {
                        Label("Add Phone Number", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(phoneNumbers.count >= 20)
                }
                Toggle("Favorite", isOn: $contact.favorite)
                if contact.favorite && favoriteNumberOptions.count > 1 {
                    Picker("Preferred Number", selection: favoriteNumberSelection) {
                        ForEach(favoriteNumberOptions) { phoneNumber in
                            Text("\(phoneNumber.label.title) · \(phoneNumber.value)")
                                .tag(phoneNumber.value)
                        }
                    }
                    .accessibilityLabel("Preferred Favorite Number")
                    .help("This number is used when you click the favorite.")
                }
                Picker("Preferred Line", selection: $contact.preferredAccountID) {
                    Text("Current Selection").tag(UUID?.none)
                    ForEach(model.snapshot.accounts) { Text($0.name).tag(Optional($0.id)) }
                }
                Section("Notes") {
                    NativeNotesEditor(text: $contact.notes)
                        .frame(minHeight: 96, idealHeight: 110, maxHeight: 130)
                }
            }.formStyle(.grouped)
            if let error { Text(error).telefonDialogErrorStyle() }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(importingPhoto)
                Spacer()
                Button("Save") {
                    contact.group = ContactGroups.normalized(contact.group)
                    contact.phoneNumbers = phoneNumbers.compactMap { entry in
                        let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                        return value.isEmpty ? nil : ContactPhoneNumber(value: value, label: entry.label)
                    }
                    do { try model.saveContact(contact); dismiss() } catch { self.error = L10n.error(error) }
                }.keyboardShortcut(.defaultAction).telefonButtonStyle(.prominent).disabled(importingPhoto)
            }.padding(20)
        }.frame(width: 560, height: 760).telefonButtonStyle().interactiveDismissDisabled(importingPhoto)
    }

    private var editorTitle: String {
        L10n.text(ContactEditorPresentation.titleKey(
            isExisting: model.snapshot.contacts.contains { $0.id == contact.id }
        ))
    }

    private var favoriteNumberOptions: [EditablePhoneNumber] {
        phoneNumbers.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var favoriteNumberSelection: Binding<String> {
        Binding {
            let options = favoriteNumberOptions
            guard let preferred = contact.favoriteNumber,
                  let current = options.first(where: { ContactFavorites.equivalent($0.value, preferred) }) else {
                return options.first?.value ?? ""
            }
            return current.value
        } set: { contact.favoriteNumber = $0 }
    }

    private func removePhoneNumber(_ id: UUID) {
        phoneNumbers.removeAll { $0.id == id }
        if phoneNumbers.isEmpty { phoneNumbers.append(EditablePhoneNumber(label: .mobile)) }
    }
}

enum ContactEditorPresentation {
    static func titleKey(isExisting: Bool) -> String {
        isExisting ? "Edit Contact" : "Add Contact"
    }
}

private struct EditablePhoneNumber: Identifiable {
    let id = UUID()
    var label: ContactPhoneLabel
    var value: String = ""

    init(label: ContactPhoneLabel) { self.label = label }
    init(_ number: ContactPhoneNumber) { label = number.label; value = number.value }
}

private extension ContactPhoneLabel {
    var title: String {
        switch self {
        case .mobile: L10n.text("Mobile")
        case .home: L10n.text("Home")
        case .work: L10n.text("Work")
        case .other: L10n.text("Other")
        }
    }
}
