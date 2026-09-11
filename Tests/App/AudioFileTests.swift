import AVFoundation
import Testing
import TelefonDomain
@testable import TelefonX

@Suite struct AudioFileTests {
    @Test func importsStereoAsOwnedMonoPCMAndKeepsOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "telefonx-audio-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Eigener Ton.wav")
        try makeTone(source)
        let original = try Data(contentsOf: source)
        let store = AudioFileStore(directory: root.appending(path: "owned"))
        let asset = try await store.importAudio(from: source)
        #expect(asset.name == "Eigener Ton")
        #expect(store.exists(asset))
        #expect(try Data(contentsOf: source) == original)
        let output = try AVAudioFile(forReading: store.url(for: asset))
        #expect(output.fileFormat.sampleRate == 48000)
        #expect(output.fileFormat.channelCount == 1)
        #expect(output.fileFormat.commonFormat == .pcmFormatInt16)
        #expect(abs(Double(output.length) - 96000) < 100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(output.length)))
        try output.read(into: buffer)
        let values = try #require(buffer.floatChannelData?[0])
        let energy = (0..<Int(buffer.frameLength)).reduce(0.0) { $0 + Double(values[$1] * values[$1]) }
        #expect(sqrt(energy / Double(buffer.frameLength)) > 0.1)
    }

    @Test func invalidAudioDoesNotCreateAssetOrChangeOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "telefonx-invalid-audio-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "bad.wav"), original = Data("Not audio".utf8)
        try original.write(to: source)
        let store = AudioFileStore(directory: root.appending(path: "owned"))
        do { _ = try await store.importAudio(from: source); Issue.record("Invalid audio accepted") } catch { }
        #expect(try Data(contentsOf: source) == original)
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }

    @Test func removesOnlyUnreferencedManagedAudioFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "telefonx-audio-cleanup-\(UUID())")
        let store = AudioFileStore(directory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = AudioAsset(name: "Verwendet")
        let orphaned = AudioAsset(name: "Verwaist")
        try Data([1]).write(to: store.url(for: retained))
        try Data([2]).write(to: store.url(for: orphaned))
        let unrelated = root.appending(path: "Hinweis.txt")
        let unknownWave = root.appending(path: "kein-asset.wav")
        try Data([3]).write(to: unrelated)
        try Data([4]).write(to: unknownWave)

        #expect(try store.removeUnreferenced(keeping: [retained.id]) == 1)
        #expect(store.exists(retained))
        #expect(!store.exists(orphaned))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(FileManager.default.fileExists(atPath: unknownWave.path))
    }

    @Test func builtinSoundFilesExist() {
        for sound in BuiltinRingtone.allCases {
            #expect(FileManager.default.fileExists(atPath: "/System/Library/Sounds/\(sound.rawValue).aiff"))
        }
    }

    private func makeTone(_ url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88200))
        buffer.frameLength = buffer.frameCapacity
        let channels = try #require(buffer.floatChannelData)
        for channel in 0..<2 { for i in 0..<88200 { channels[channel][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100) * 0.4) } }
        var settings = format.settings; settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }
}
