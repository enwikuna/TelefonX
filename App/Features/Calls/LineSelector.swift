import SwiftUI
import TelefonDomain

struct LineSelector: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openWindow) private var openWindow
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
                            let locked = model.isAccountLockedByPro(account.id)
                            let state = model.registrations[account.id] ?? .offline
                            Button {
                                if locked { openWindow(id: "pro") }
                                else { model.selectedAccountID = account.id }
                            } label: {
                                HStack(spacing: 10) {
                                    RegistrationIndicator(state: locked ? .disabled : state)
                                    Text(account.name).font(.callout.weight(.medium)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: locked ? "lock.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                                        .foregroundStyle(locked ? Color.secondary : (selected ? Color.accentColor : Color.secondary))
                                }.padding(.vertical, 3).frame(maxWidth: .infinity)
                            }
                            .buttonBorderShape(.capsule).telefonButtonStyle()
                            .opacity(locked ? 0.62 : 1)
                            .accessibilityLabel(L10n.format("Line %@", account.name))
                            .accessibilityValue(locked
                                ? L10n.text("Locked · TelefonX Pro")
                                : "\(selected ? L10n.text("Selected, ") : "")\(RegistrationIndicator(state: state).label)")
                            .accessibilityAddTraits(selected && !locked ? .isSelected : [])
                            .help(locked
                                ? L10n.format("%@ · Locked · TelefonX Pro", account.name)
                                : "\(account.name) · \(RegistrationIndicator(state: state).label)")
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
