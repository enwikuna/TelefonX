import SwiftUI
import TelefonDomain

struct CallCard: View {
    @Environment(PhoneModel.self) private var model
    let call: CallSession
    let consultation: () -> Void
    @State private var showKeypad = false
    private var waiting: Bool { call.incoming && call.answeredAt == nil }
    private var connected: Bool { call.phase == .connected }
    private var canSendTones: Bool { CallPresentation.canSendTones(call) }
    private var compactIdentity: Bool { showKeypad || model.activeCalls.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    identity
                    if !waiting {
                        controls
                        if showKeypad {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Keypad Tones").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                Keypad(compact: true) { digit in
                                    sendTone(digit)
                                }.disabled(!canSendTones)
                            }
                        }
                        multiCallActions
                    }
                    AudioWarningView()
                    if call.mediaError != 0 {
                        Label("Audio Connection Interrupted", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, CallWorkspaceLayout.horizontalContentInset)
                .padding(.vertical, CallWorkspaceLayout.verticalContentInset)
            }
            endControls
                .padding(.horizontal, CallWorkspaceLayout.horizontalContentInset)
                .padding(.vertical, CallWorkspaceLayout.verticalContentInset)
        }
        .background {
            CallKeyboardShortcut(
                enabled: connected && !model.callOperationPending,
                dtmfEnabled: showKeypad && canSendTones,
                hold: { Task { await model.hold(call) } },
                mute: { Task { await model.mute(call) } },
                dtmf: sendTone
            )
            .frame(width: 0, height: 0)
        }
    }

    private var identity: some View {
        VStack(spacing: 10) {
            HStack {
                Text(model.accountName(call.accountID))
                if compactIdentity, let date = call.answeredAt { Spacer(); Text(date, style: .timer).monospacedDigit() }
            }.font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            if !compactIdentity {
                ContactAvatar(contact: model.displayContact(for: call.remote), size: 64).padding(.vertical, 8)
            }
            Text(model.displayName(call.remote)).font(.system(size: compactIdentity ? 22 : 26, weight: .semibold))
                .multilineTextAlignment(.center).lineLimit(3).textSelection(.enabled)
            if !compactIdentity && model.displayName(call.remote) != call.remote {
                Text(call.remote).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(CallPresentation.status(call, inConference: model.isInConference(call)))
                .font(.callout)
                .foregroundStyle(call.held ? .orange : .secondary)
            if !compactIdentity, let date = call.answeredAt {
                Text(date, style: .timer).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, compactIdentity ? 0 : 8)
    }

    private var controls: some View {
        GlassControls(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                control(call.muted ? "Unmute" : "Mute", icon: call.muted ? "mic.slash.fill" : "mic.fill", selected: call.muted) {
                    Task { await model.mute(call) }
                }
                .disabled(!connected)
                .help(call.muted ? "Unmute Microphone (M)" : "Mute Microphone (M)")
                control(call.held ? "Resume" : "Hold", icon: call.held ? "play.fill" : "pause.fill", selected: call.held) {
                    Task { await model.hold(call) }
                }
                .disabled(!connected || model.callOperationPending)
                .help(call.held ? "Resume Call (H)" : "Hold Call (H)")
                control("Keypad", icon: "circle.grid.3x3.fill", selected: showKeypad) {
                    showKeypad.toggle()
                }
                .disabled(!canSendTones)
                .help(call.held ? "Resume the call to send keypad tones" : "Open Keypad")
                control("Consultation …", icon: "phone.badge.plus", action: consultation)
                    .disabled(!connected || model.callOperationPending || !model.conferenceHandles.isEmpty)
            }
        }
        .onChange(of: call.held) { _, held in
            if held { showKeypad = false }
        }
    }

    private func control(_ title: String, icon: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium))
                Text(L10n.text(title)).font(.callout.weight(.medium))
            }.frame(maxWidth: .infinity).frame(height: 65)
        }
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .telefonButtonStyle(selected ? .prominent : .regular)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sendTone(_ digit: String) {
        if let character = digit.first { model.dialTones.play(character, outputUID: model.outputUID) }
        Task { await model.tone(digit, call: call) }
    }

    @ViewBuilder private var multiCallActions: some View {
        if let other = CallPresentation.pairedCall(for: call, in: model.activeCalls) {
            GlassControls(spacing: 10) {
                HStack(spacing: 10) {
                    conferenceControl(other)
                    transferControl(other)
                        .disabled(model.callOperationPending || model.isInConference(call))
                }
            }
        }
    }

    private func transferControl(_ other: CallSession) -> some View {
        Button {
            Task { await model.transfer(call, consultation: other) }
        } label: {
            transferLabel
        }
        .telefonButtonStyle()
        .help(L10n.format("Transfer Call to %@", model.displayName(other.remote)))
        .accessibilityLabel(L10n.format("Transfer Call to %@", model.displayName(other.remote)))
    }

    @ViewBuilder private func conferenceControl(_ other: CallSession) -> some View {
        if model.isInConference(call) {
            Button {
                Task { await model.endConference(keeping: call) }
            } label: {
                Label("End Conference", systemImage: "person.3.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .telefonButtonStyle(.prominent)
            .disabled(model.callOperationPending)
        } else {
            Button {
                Task { await model.startConference(call, with: other) }
            } label: {
                Label("Conference", systemImage: "person.3.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .telefonButtonStyle()
            .disabled(model.callOperationPending || !model.conferenceHandles.isEmpty)
            .help("Merge calls into a conference")
        }
    }

    private var transferLabel: some View {
        Label("Transfer", systemImage: "arrow.triangle.branch")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private var endControls: some View {
        GlassControls {
            HStack(spacing: 10) {
                Button { Task { await model.hangup(call) } } label: {
                    Label(L10n.text(waiting ? "Decline" : "Hang Up"), systemImage: "phone.down.fill")
                        .font(.headline).foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                }.telefonButtonStyle(.prominent).tint(TelephonyColors.end)
                    .accessibilityIdentifier("hangup-call")
                if waiting {
                    Button { Task { await model.answer(call) } } label: {
                        Label("Answer", systemImage: "phone.fill")
                            .font(.headline).foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }.telefonButtonStyle(.prominent).tint(TelephonyColors.call)
                        .disabled(model.callOperationPending)
                }
            }.buttonBorderShape(.roundedRectangle(radius: 14))
        }
    }
}
