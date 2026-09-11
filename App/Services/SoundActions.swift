import Foundation
import TelefonDomain

extension PhoneModel {
    func saveHoldMusic(_ asset: AudioAsset?) async throws {
        if asset != nil { try requirePro(.holdMusic) }
        guard activeCalls.isEmpty, !callOperationPending, !configurationBusy else { throw AppError.callInProgress }
        configurationBusy = true; defer { configurationBusy = false }
        if let asset { guard audioFiles.exists(asset) else { throw SoundError.missing } }
        let previous = snapshot.holdMusic
        do {
            if ready { try await engine.setHoldMusic(asset.map(audioFiles.url)) }
            if asset != nil { try requirePro(.holdMusic) }
            var next = snapshot
            next.holdMusic = asset
            try commit(next)
        }
        catch {
            var engineRestored = !ready
            if ready {
                do {
                    let restoredAsset = purchases.access.permits(.holdMusic) ? previous : nil
                    try await engine.setHoldMusic(restoredAsset.flatMap { audioFiles.exists($0) ? audioFiles.url(for: $0) : nil })
                    engineRestored = true
                } catch {}
            }
            if engineRestored, let asset { removeAudioIfUnreferenced(asset) }
            throw error
        }
        if let previous { removeAudioIfUnreferenced(previous) }
        holdMusicWarning = nil
    }

    func removeUnreferencedAudioFiles() {
        _ = try? audioFiles.removeUnreferenced(keeping: referencedAudioAssetIDs)
    }

    func restoreHoldMusic() async {
        let asset = purchases.access.permits(.holdMusic) ? snapshot.holdMusic : nil
        let available = asset.flatMap { audioFiles.exists($0) ? audioFiles.url(for: $0) : nil }
        do {
            try await engine.setHoldMusic(available)
            holdMusicWarning = asset != nil && available == nil ? L10n.text("Hold music is missing on this Mac. Choose it again.") : nil
        } catch { holdMusicWarning = L10n.text("Hold music could not be applied. Choose it again under Audio.") }
    }

    private var referencedAudioAssetIDs: Set<UUID> {
        var ids = Set(snapshot.accounts.compactMap { account -> UUID? in
            guard case .file(let asset) = account.ringtone else { return nil }
            return asset.id
        })
        if let holdMusic = snapshot.holdMusic { ids.insert(holdMusic.id) }
        return ids
    }

    private func removeAudioIfUnreferenced(_ asset: AudioAsset) {
        guard !referencedAudioAssetIDs.contains(asset.id) else { return }
        audioFiles.remove(asset)
    }
}
