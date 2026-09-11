import SwiftUI
import UniformTypeIdentifiers
import TelefonDomain

struct ContactPhotoPicker: View {
    @Binding var contact: PhoneContact
    @Binding var importing: Bool
    @State private var choosing = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 4) {
            Button { choosing = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    ContactAvatar(contact: contact, size: 92)
                    photoActionBadge
                }
            }
            .buttonStyle(.plain)
            .padding(10)
            .disabled(importing)
            .help(contact.photoData == nil ? "Choose Contact Photo …" : "Change Contact Photo …")
            .accessibilityLabel(contact.photoData == nil ? "Choose Contact Photo …" : "Change Contact Photo …")

            if importing {
                ProgressView().controlSize(.small).accessibilityLabel("Processing Contact Photo")
            } else if contact.photoData != nil {
                Button("Remove Photo") { contact.photoData = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                importing = true
                Task {
                    defer { importing = false }
                    do { contact.photoData = try await Task.detached(priority: .userInitiated) { try ContactPhotoCodec.importFile(url) }.value }
                    catch { self.error = L10n.error(error) }
                }
            case .failure(let error): self.error = L10n.error(error)
            }
        }
        .alert("Contact Photo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private var photoActionBadge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 12, weight: .semibold))
            .padding(7)
            .glassEffect(.regular.interactive(), in: Circle())
    }
}
