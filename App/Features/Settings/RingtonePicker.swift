import SwiftUI
import UniformTypeIdentifiers
import TelefonDomain

struct RingtonePicker: View {
    @Environment(PhoneModel.self) private var model
    @Binding var selection: LineRingtone?
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    @State private var preview = SoundPlayback()
    var body: some View {
        Section("Ringtone for This Line") {
            Picker("Ringtone", selection: Binding(get: { model.effectiveRingtone(selection) }, set: { value in
                selection = value
                playPreview(value)
            })) {
                ForEach(BuiltinRingtone.allCases, id: \.self) { sound in Text(sound.title).tag(LineRingtone.system(sound)) }
                if model.purchases.access.permits(.customRingtones), case .file(let asset) = selection {
                    Text(asset.name).tag(LineRingtone.file(asset))
                }
            }
            HStack {
                Button(preview.isPlaying ? "Stop" : "Preview Audio", systemImage: preview.isPlaying ? "stop.fill" : "play.fill") {
                    if preview.isPlaying { preview.stop() }
                    else { playPreview(selection ?? .system(.glass)) }
                }
                if model.purchases.access.permits(.customRingtones) {
                    Button(busy ? "Importing" : "Custom Audio File …") { importing = true }.disabled(busy)
                } else {
                    ProAccessButton("Custom Ringtones with TelefonX Pro …")
                }
            }
            if case .file(let asset) = selection, !model.audioFiles.exists(asset) {
                Text("The file is missing on this Mac. The default ringtone will be used until you choose it again.").font(.caption).foregroundStyle(.orange)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            busy = true
            Task {
                defer { busy = false }
                do {
                    try model.requirePro(.customRingtones)
                    let asset = try await model.audioFiles.importAudio(from: result.get())
                    try model.requirePro(.customRingtones)
                    selection = .file(asset)
                    preview.stop()
                }
                catch { self.error = L10n.error(error) }
            }
        }
        .onDisappear { preview.stop() }
        .onChange(of: model.purchases.access) { _, access in
            if !access.permits(.customRingtones) { preview.stop(); importing = false }
        }
        .alert("Ringtone", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func playPreview(_ ringtone: LineRingtone) {
        preview.stop()
        do {
            try preview.play(Ringer.url(for: model.effectiveRingtone(ringtone), library: model.audioFiles),
                             outputUID: model.ringtoneUID, looping: false)
        } catch {
            self.error = L10n.error(error)
        }
    }
}
