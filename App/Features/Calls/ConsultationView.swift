import AppKit
import SwiftUI
import TelefonDomain

enum ConsultationContactPresentation {
    static func contacts(_ contacts: [PhoneContact], search: String) -> [PhoneContact] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return contacts.filter { contact in
            query.isEmpty || [contact.name, contact.company, contact.group, contact.numbers.joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { left, right in
            if left.favorite != right.favorite { return left.favorite }
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.id.uuidString < right.id.uuidString : order == .orderedAscending
        }
    }
}

struct ConsultationView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case dialer = "Dial"
        case contacts = "Contacts"
        var id: Self { self }
    }

    @Environment(PhoneModel.self) private var model
    @State private var mode = Mode.dialer
    @State private var search = ""
    let started: (CallHandle) -> Void
    let close: () -> Void

    private var contacts: [PhoneContact] {
        ConsultationContactPresentation.contacts(
            model.snapshot.contacts + model.visibleAppleContacts.map(\.presentationContact), search: search
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Consultation").font(.title2.weight(.semibold))
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction).telefonButtonStyle()
            }
            Text("The current call is placed on hold when you call.")
                .font(.callout).foregroundStyle(.secondary)
            ConsultationModePicker(selection: $mode)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            Group {
                switch mode {
                case .dialer:
                    ScrollView {
                        DialerView(onCallStarted: started)
                            .padding(.horizontal, 1)
                            .padding(.bottom, 1)
                    }
                    .scrollIndicators(.automatic)
                case .contacts:
                    contactPicker
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
        // Fit the header, mode control, and complete dialer without scrolling.
        .frame(width: 440, height: 700, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var contactPicker: some View {
        VStack(spacing: 12) {
            TextField("Search Contacts Action", text: $search)
                .textFieldStyle(.roundedBorder)
            if contacts.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No Contacts" : "No Contacts Found",
                    systemImage: "person.crop.circle",
                    description: Text(search.isEmpty ? "Add contacts first." : "Try another contact name or number.")
                )
            } else {
                List(contacts) { contact in
                    HStack(spacing: 10) {
                        ContactAvatar(contact: contact, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(contact.name).font(.body.weight(.medium)).lineLimit(1)
                                if contact.favorite {
                                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                                }
                            }
                            Text(contactDetail(contact)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        callControl(contact)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder private func callControl(_ contact: PhoneContact) -> some View {
        let callable = contact.numbers.filter { model.canCall($0, preferredAccountID: contact.preferredAccountID) }
        if contact.numbers.count > 1 {
            Menu {
                ForEach(contact.numbers, id: \.self) { number in
                    Button(number) { call(number, contact: contact) }
                        .disabled(!callable.contains(number))
                }
            } label: {
                RowActionIcon(systemName: "phone.fill")
            }
            .telefonRowActionMenuStyle()
            .disabled(callable.isEmpty)
            .help("Choose Number for Consultation")
        } else {
            Button {
                if let number = contact.numbers.first { call(number, contact: contact) }
            } label: {
                RowActionIcon(systemName: "phone.fill")
            }
            .buttonBorderShape(.circle)
            .telefonButtonStyle()
            .disabled(callable.isEmpty)
            .help("Start Consultation")
        }
    }

    private func contactDetail(_ contact: PhoneContact) -> String {
        let number = ContactFavorites.number(for: contact) ?? "No Phone Number"
        return [contact.company, number].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func call(_ number: String, contact: PhoneContact) {
        Task {
            if let handle = await model.callNumber(number, preferredAccountID: contact.preferredAccountID) {
                started(handle)
            }
        }
    }
}

/// SwiftUI's segmented picker currently drops the SF Symbols and keeps its
/// intrinsic width on macOS. This narrow AppKit bridge preserves the native
/// segmented-control appearance while SwiftUI remains the source of truth.
struct ConsultationModePicker: NSViewRepresentable {
    @Binding var selection: ConsultationView.Mode

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> Container {
        let container = Container()
        Self.configure(container.control)
        container.control.target = context.coordinator
        container.control.action = #selector(Coordinator.selectionChanged(_:))
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        context.coordinator.selection = $selection
        let selectedSegment = selection == .dialer ? 0 : 1
        if container.control.selectedSegment != selectedSegment {
            container.control.selectedSegment = selectedSegment
        }
    }

    static func configure(_ control: NSSegmentedControl) {
        control.segmentCount = 2
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.segmentStyle = .automatic
        control.controlSize = .large
        control.setLabel(L10n.text("Dial"), forSegment: 0)
        control.setLabel(L10n.text("Contacts"), forSegment: 1)
        control.setImage(NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: nil), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil), forSegment: 1)
        control.setImageScaling(.scaleProportionallyDown, forSegment: 0)
        control.setImageScaling(.scaleProportionallyDown, forSegment: 1)
        control.setAccessibilityLabel(L10n.text("Consult Using"))
    }

    final class Container: NSView {
        let control = NSSegmentedControl()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: leadingAnchor),
                control.trailingAnchor.constraint(equalTo: trailingAnchor),
                control.topAnchor.constraint(equalTo: topAnchor),
                control.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: control.intrinsicContentSize.height)
        }
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<ConsultationView.Mode>

        init(selection: Binding<ConsultationView.Mode>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            selection.wrappedValue = sender.selectedSegment == 1 ? .contacts : .dialer
        }
    }
}
