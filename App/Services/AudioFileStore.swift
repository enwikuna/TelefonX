import AVFoundation
import TelefonDomain

/// Owned, normalized audio files, not security-scoped links to the user's originals.
struct AudioFileStore: Sendable {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "TelefonX/Audio", directoryHint: .isDirectory)
    }
    func url(for asset: AudioAsset) -> URL { directory.appending(path: asset.id.uuidString + ".wav") }
    func exists(_ asset: AudioAsset) -> Bool { FileManager.default.fileExists(atPath: url(for: asset).path) }

    func remove(_ asset: AudioAsset) {
        try? FileManager.default.removeItem(at: url(for: asset))
    }

    @discardableResult
    func removeUnreferenced(keeping assetIDs: Set<UUID>) throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        for file in files where file.pathExtension.lowercased() == "wav" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  !assetIDs.contains(id) else { continue }
            try FileManager.default.removeItem(at: file)
            removed += 1
        }
        return removed
    }

    func importAudio(from source: URL) async throws -> AudioAsset {
        try await Task.detached(priority: .userInitiated) { try convert(source) }.value
    }
    private func convert(_ source: URL) throws -> AudioAsset {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let metadata = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard metadata.isRegularFile == true, (metadata.fileSize ?? Int.max) <= 100_000_000 else { throw SoundError.tooLarge }
        let input = try AVAudioFile(forReading: source)
        let inputFormat = input.processingFormat
        let duration = Double(input.length) / inputFormat.sampleRate
        guard duration.isFinite, duration > 0, duration <= 600 else { throw SoundError.tooLong }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: format),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4096),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { throw SoundError.unsupported }
        let asset = AudioAsset(name: String(source.deletingPathExtension().lastPathComponent.prefix(200)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = url(for: asset)
        do {
            let output = try AVAudioFile(forWriting: destination, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            let feeder = AudioConversionInput(file: input, buffer: sourceBuffer)
            var total: AVAudioFramePosition = 0
            while true {
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { count, state in
                    feeder.read(count: count, status: state)
                }
                if let readError = feeder.error { throw readError }
                if let conversionError { throw conversionError }
                if status == .error { throw SoundError.unsupported }
                if outputBuffer.frameLength > 0 {
                    try output.write(from: outputBuffer)
                    total += AVAudioFramePosition(outputBuffer.frameLength)
                }
                guard total <= 48000 * 600 else { throw SoundError.tooLong }
                if status == .endOfStream { break }
            }
            guard total > 0 else { throw SoundError.unsupported }
            return asset
        } catch {
            // Only the new UUID-named import is removed; the source is untouched.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

/// AVAudioConverter invokes its input block synchronously. This object and its
/// buffer never escape that one converter/worker task; error publication is locked.
private final class AudioConversionInput: @unchecked Sendable {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var failure: Error?
    init(file: AVAudioFile, buffer: AVAudioPCMBuffer) { self.file = file; self.buffer = buffer }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return failure }
    func read(count: AVAudioPacketCount, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard file.framePosition < file.length else { status.pointee = .endOfStream; return nil }
        do {
            let remaining = AVAudioFrameCount(min(file.length - file.framePosition, AVAudioFramePosition(buffer.frameCapacity)))
            try file.read(into: buffer, frameCount: min(count, remaining))
            status.pointee = buffer.frameLength == 0 ? .endOfStream : .haveData
            return buffer.frameLength == 0 ? nil : buffer
        } catch { failure = error; status.pointee = .endOfStream; return nil }
    }
}

enum SoundError: LocalizedError {
    case tooLarge, tooLong, unsupported, missing
    var errorDescription: String? {
        switch self {
        case .tooLarge: L10n.text("Choose an audio file no larger than 100 MB.")
        case .tooLong: L10n.text("The audio file is empty or longer than ten minutes.")
        case .unsupported: L10n.text("This audio file cannot be read. Use an unprotected WAV, AIFF, MP3, or M4A file.")
        case .missing: L10n.text("The audio file is missing on this Mac. Choose it again.")
        }
    }
}
