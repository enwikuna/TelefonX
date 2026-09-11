import AppKit
import SwiftUI
import TelefonDomain

struct AppleContactRow: View {
    @Environment(PhoneModel.self) private var model
    let contact: AppleContact
    let selected: Bool
    let selectionCount: Int
    let copyToLocal: () -> Void

    private var presentation: PhoneContact { contact.presentationContact }
    private var displayedNumber: String { contact.numbers.first ?? "" }
    private var detail: String {
        [contact.company, displayedNumber].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: HistoryRowLayout.avatarTextSpacing) {
            ContactAvatar(contact: presentation)
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name).font(.body.weight(.medium)).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                callControl
                Button(action: copyToLocal) { RowActionIcon(systemName: "plus.circle", tint: .secondary) }
                    .buttonBorderShape(.circle).telefonButtonStyle()
                    .help("Copy to TelefonX …")
                    .accessibilityLabel("Copy to TelefonX …")
                    .accessibilityIdentifier("apple-contact-copy")
            }
        }
        .padding(.horizontal, HistoryRowLayout.contentHorizontalInset)
        .frame(height: ContactTable.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: HistoryRowLayout.selectionCornerRadius)
                    .fill(Color.primary.opacity(0.08))
                    .padding(.horizontal, HistoryRowLayout.selectionHorizontalInset)
                    .padding(.vertical, HistoryRowLayout.selectionVerticalInset)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, HistoryRowLayout.nativeSelectionSurfaceHorizontalInset)
        .contextMenu {
            if selectionCount <= 1 {
                Button("Copy to TelefonX …", systemImage: "person.crop.circle.badge.plus", action: copyToLocal)
                if contact.numbers.count == 1 {
                    Button("Copy Number", systemImage: "doc.on.doc") { copy(contact.numbers[0]) }
                } else if !contact.numbers.isEmpty {
                    Menu("Copy Number", systemImage: "doc.on.doc") {
                        ForEach(contact.numbers, id: \.self) { number in Button(number) { copy(number) } }
                    }
                }
            }
        }
    }

    @ViewBuilder private var callControl: some View {
        if contact.numbers.count > 1 {
            Menu {
                ForEach(contact.numbers, id: \.self) { number in
                    Button(number) { performCall(number) }
                }
            } label: {
                RowActionIcon(systemName: "phone.fill")
            }
            .telefonRowActionMenuStyle()
            .help("Choose Number")
            .accessibilityLabel(L10n.format("%@, Choose Number", contact.name))
        } else {
            Button {
                if !displayedNumber.isEmpty { performCall(displayedNumber) }
            } label: {
                RowActionIcon(systemName: "phone.fill")
            }
            .buttonBorderShape(.circle)
            .telefonButtonStyle()
            .disabled(displayedNumber.isEmpty)
            .help(listCallActionTitle)
            .accessibilityLabel(L10n.format("%@, %@", contact.name,
                                            listCallActionTitle))
        }
    }

    private func performCall(_ number: String) {
        Task { await model.performListCall(number, preferredAccountID: nil) }
    }

    private var listCallActionTitle: String {
        if !model.activeCalls.isEmpty { return L10n.text("Start Consultation") }
        return L10n.text(model.automaticallyStartListCalls ? "Place Call" : "Use Number")
    }

    private func copy(_ number: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(number, forType: .string)
    }
}

struct ContactSourceHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, HistoryRowLayout.contentHorizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, CenterColumnSectionLayout.titleBottomInset)
        .accessibilityElement(children: .combine)
    }
}
