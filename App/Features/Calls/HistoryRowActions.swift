import SwiftUI

struct HistoryRowActions: View {
    let name: String
    let hasDestination: Bool
    let startsConsultation: Bool
    let startsCallImmediately: Bool
    let prepareCall: () -> Void

    private var actionTitle: String {
        if startsConsultation { return L10n.text("Start Consultation") }
        return L10n.text(startsCallImmediately ? "Place Call" : "Use Number for Callback")
    }

    var body: some View {
        Button(action: prepareCall) {
            RowActionIcon(systemName: "phone.fill")
        }
        .telefonButtonStyle().buttonBorderShape(.circle)
        .disabled(!hasDestination)
        .help(actionTitle)
        .accessibilityLabel(startsConsultation
                            ? L10n.format("Start Consultation with %@", name)
                            : L10n.format(startsCallImmediately ? "Call %@" : "Use %@ for Callback", name))
        .accessibilityIdentifier("history-callback")
    }
}
