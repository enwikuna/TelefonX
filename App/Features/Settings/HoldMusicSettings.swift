import SwiftUI
import UniformTypeIdentifiers
import TelefonDomain

struct HoldMusicSettings: View {
    @Environment(PhoneModel.self) private var model
    @State private var importing = false
    @State private var busy = false
    @State private var preview = SoundPlayback()
    var body: some View {
        Section {
            Group {
                LabeledContent("Audio File", value: model.snapshot.holdMusic?.name ?? "No Custom Hold Music")
                HStack {
                    Button(busy ? "Importing" : "Choose Audio File …") { importing = true }
                        .disabled(busy || !model.activeCalls.isEmpty || model.configurationBusy)
                    if let asset = model.snapshot.holdMusic {
                        Button(preview.isPlaying ? "Stop" : "Preview Audio", systemImage: preview.isPlaying ? "stop.fill" : "play.fill") {
                            if preview.isPlaying { preview.stop() }
                            else { do { try preview.play(model.audioFiles.url(for: asset), outputUID: model.outputUID, looping: false) } catch { model.report(error) } }
                        }.disabled(!model.activeCalls.isEmpty)
                        Button("Remove", role: .destructive) { Task { do { try await model.saveHoldMusic(nil); preview.stop() } catch { model.report(error) } } }
                            .tint(.red)
                            .disabled(busy || !model.activeCalls.isEmpty || model.configurationBusy)
                    }
                }
            }
            .disabled(!model.purchases.access.permits(.holdMusic))
            if !model.purchases.access.permits(.holdMusic) {
                ProAccessButton("Custom Hold Music with TelefonX Pro …")
            }
            if let asset = model.snapshot.holdMusic, !model.audioFiles.exists(asset) {
                Text("The file is missing on this Mac. Please choose it again.").font(.caption).foregroundStyle(.orange)
            }
            if let warning = model.holdMusicWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
        } header: { Text("Hold Music") } footer: {
            Text("The party on hold hears this music in a loop until the call resumes. Use an unprotected WAV, AIFF, MP3, or M4A file up to 10 minutes or 100 MB. Your phone system may play its own hold music instead.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            busy = true
            Task {
                defer { busy = false }
                do {
                    try model.requirePro(.holdMusic)
                    let asset = try await model.audioFiles.importAudio(from: result.get())
                    try await model.saveHoldMusic(asset)
                }
                catch { model.report(error) }
            }
        }
        .onDisappear { preview.stop() }
        .onChange(of: model.purchases.access) { _, access in
            if !access.permits(.holdMusic) { preview.stop(); importing = false }
        }
    }
}
