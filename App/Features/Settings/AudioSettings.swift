import SwiftUI
import TelefonDomain

struct AudioSettings: View {
    @Environment(PhoneModel.self) private var model
    @State private var preview = SoundPlayback()
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Call") {
                devicePicker("Microphone", selection: $model.inputUID, input: true)
                devicePicker("Playback", selection: $model.outputUID, input: false)
                Button(model.activeCalls.isEmpty ? "Refresh Audio Devices" : "Apply Selection to Call") {
                    Task {
                        if model.activeCalls.isEmpty { await model.refreshDevices() }
                        else { do { try await model.activateAudio() } catch { model.report(error) } }
                    }
                }
            }
            Section("Ringing") {
                devicePicker("Ringtone Output", selection: $model.ringtoneUID, input: false)
                Button("Test Ringtone Output") {
                    do { try preview.play(Ringer.url(for: .system(.glass), library: model.audioFiles), outputUID: model.ringtoneUID, looping: false) }
                    catch { model.report(error) }
                }
            }
            HoldMusicSettings()
            if let warning = model.audioWarning { Text(warning).foregroundStyle(.orange) }
        }.formStyle(.grouped).task { await model.refreshDevices() }.onDisappear { preview.stop() }
    }
    private func devicePicker(_ title: LocalizedStringKey, selection: Binding<String>, input: Bool) -> some View {
        Picker(title, selection: selection) {
            Text("System Default").tag("")
            ForEach(model.devices.filter { input ? $0.inputChannels > 0 : $0.outputChannels > 0 }) { Text($0.name).tag($0.id) }
            if !selection.wrappedValue.isEmpty && !model.devices.contains(where: { $0.id == selection.wrappedValue }) {
                Text("Disconnected (Saved Selection)").tag(selection.wrappedValue)
            }
        }
    }
}
