import SwiftUI
import TelefonDomain

/// A call replaces the idle dialer. A second destination is an explicit consultation.
struct CallWorkspace: View {
    @Environment(PhoneModel.self) private var model
    @State private var selection: CallHandle?
    @State private var consultation = false
    private var presentedCalls: [CallSession] { model.presentedCalls }
    private var selected: CallSession? { CallPresentation.selected(in: presentedCalls, preferred: selection) }

    var body: some View {
        Group {
            if let call = selected {
                VStack(spacing: 0) {
                    if presentedCalls.count > 1 {
                        participantSwitcher
                            .padding(.horizontal, CallWorkspaceLayout.horizontalContentInset)
                            .padding(.top, CallWorkspaceLayout.verticalContentInset)
                    }
                    CallCard(call: call, consultation: { consultation = true }).id(call.handle)
                }
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        IdleDialerLayout(availableHeight: geometry.size.height) {
                            VStack(spacing: 20) { DialerView(); AudioWarningView() }
                                .padding(.horizontal, CallWorkspaceLayout.horizontalContentInset)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: presentedCalls.map(\.handle)) { old, new in
            if let added = presentedCalls.first(where: { !old.contains($0.handle) }) {
                selection = added.handle
                consultation = false
            }
            if new.isEmpty { consultation = false }
        }
        .sheet(isPresented: $consultation) {
            ConsultationView(
                started: { handle in selection = handle; consultation = false },
                close: { consultation = false }
            )
        }
    }

    @ViewBuilder private var participantSwitcher: some View {
        let visibleRows = min(presentedCalls.count, 3)
        let height = CGFloat(visibleRows) * 58 + 4
        if presentedCalls.count > visibleRows {
            ScrollView {
                callSwitcher.padding(2)
            }
            .scrollEdgeEffectHidden(for: .top)
            .frame(height: height)
        } else {
            callSwitcher.padding(2).frame(height: height)
        }
    }

    private var callSwitcher: some View {
        // Keep each row in its own glass rendering group. The surrounding
        // scroll view provides the small overflow margin required by the native
        // glass outline, so none of its corners are clipped.
        VStack(spacing: 8) {
            ForEach(presentedCalls) { call in
                Button { selection = call.handle } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.displayName(call.remote)).font(.callout.weight(.medium)).lineLimit(1)
                            Text(CallPresentation.status(call, inConference: model.isInConference(call)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected?.handle == call.handle { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .telefonButtonStyle()
                .accessibilityAddTraits(selected?.handle == call.handle ? .isSelected : [])
            }
        }
    }
}

enum CallWorkspaceLayout {
    static let horizontalContentInset: CGFloat = 16
    static let verticalContentInset: CGFloat = 20
}



struct AudioWarningView: View {
    @Environment(PhoneModel.self) private var model
    var body: some View {
        if let warning = model.audioWarning {
            VStack(alignment: .leading, spacing: 10) {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                Button("Reconnect Audio") {
                    Task { do { try await model.activateAudio() } catch { model.report(error) } }
                }.telefonButtonStyle()
            }
        }
    }
}
