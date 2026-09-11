import SwiftUI
import TelefonDomain

struct LineSelector: View {
    @Environment(PhoneModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Call Using")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, LineSelectorLayout.labelLeadingInset)
            if model.snapshot.accounts.isEmpty {
                Label("No Line Yet", systemImage: "phone.badge.plus").font(.callout).foregroundStyle(.secondary)
            } else {
                GlassControls(spacing: 8) {
                    VStack(spacing: 8) {
                        ForEach(model.snapshot.accounts) { account in
                            let selected = model.selectedAccountID == account.id
                            let state = model.registrations[account.id] ?? .offline
                            Button { model.selectedAccountID = account.id } label: {
                                HStack(spacing: 10) {
                                    RegistrationIndicator(state: state)
                                    Text(account.name).font(.callout.weight(.medium)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                }.padding(.vertical, 3).frame(maxWidth: .infinity)
                            }
                            .buttonBorderShape(.capsule).telefonButtonStyle()
                            .accessibilityLabel(L10n.format("Line %@", account.name))
                            .accessibilityValue("\(selected ? L10n.text("Selected, ") : "")\(RegistrationIndicator(state: state).label)")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .help("\(account.name) · \(RegistrationIndicator(state: state).label)")
                        }
                    }
                }
            }
        }
    }
}

enum LineSelectorLayout {
    /// Native glass buttons draw their visible capsule inside the layout bounds.
    static let labelLeadingInset: CGFloat = 4
}
