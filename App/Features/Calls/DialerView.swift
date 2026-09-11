import SwiftUI
import TelefonDomain

struct DialerView: View {
    @Environment(PhoneModel.self) private var model
    var onCallStarted: ((CallHandle) -> Void)?
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            LineSelector()
            dialEntry
            Keypad { digit in
                if let character = digit.first { model.dialTones.play(character, outputUID: model.outputUID) }
                model.dialText += digit
            }
            callButton
        }
    }

    private var dialEntry: some View {
        ZStack(alignment: .center) {
            DialNumberField(text: Bindable(model).dialText) { digit in
                model.dialTones.play(digit, outputUID: model.outputUID)
            } onSubmit: {
                if model.canDial { startCall() }
            }
            .frame(height: 28)
            .padding(.horizontal, 32)

            HStack(spacing: 0) {
                Spacer()
                Button {
                    guard !model.dialText.isEmpty else { return }
                    model.dialText.removeLast()
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 28, height: 28, alignment: .center)
                        .offset(y: -4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(model.dialText.isEmpty ? 0 : 1)
                .allowsHitTesting(!model.dialText.isEmpty)
                .accessibilityHidden(model.dialText.isEmpty)
                .accessibilityLabel("Delete Last Character")
                .help("Delete Last Character")
                .frame(width: 32, height: 28, alignment: .center)
            }
            .frame(height: 28, alignment: .center)
        }
        .frame(height: 32)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var callButton: some View {
        if model.canDial {
            Button(action: performDialAction) { callButtonLabel }
                .buttonBorderShape(.roundedRectangle(radius: 13))
                .telefonButtonStyle(.prominent)
                .tint(.green)
                .disabled(!model.canUseDialAction)
                .help("Call (⌘↩)")
                .accessibilityLabel("Place Call")
        } else {
            Button(action: performDialAction) { callButtonLabel }
                .buttonBorderShape(.roundedRectangle(radius: 13))
                .telefonButtonStyle()
                .disabled(!model.canUseDialAction)
                .help(model.dialText.isEmpty
                      ? model.redialHelp
                      : "Enter a valid number")
                .accessibilityLabel(model.dialText.isEmpty
                                    ? model.redialAccessibilityLabel
                                    : L10n.text("Place Call"))
        }
    }

    private var callButtonLabel: some View {
        Label(
            model.callOperationPending
                ? "Connecting …"
                : (model.dialText.isEmpty && model.hasRedialTarget ? "Redial" : "Place Call"),
            systemImage: "phone.fill"
        )
        .font(.headline)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
    }

    private func performDialAction() {
        Task {
            if let handle = await model.performDialAction() { onCallStarted?(handle) }
        }
    }

    private func startCall() {
        Task { if let handle = await model.dial() { onCallStarted?(handle) } }
    }
}
