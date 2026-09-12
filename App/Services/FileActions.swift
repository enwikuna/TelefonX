import AppKit
import UniformTypeIdentifiers
import TelefonDomain
import TelefonData

@MainActor enum FileActions {
    static func exportRemindersCSV(_ model: PhoneModel) {
        save(Data(RemindersCSV.encode(model.snapshot.reminders).utf8),
             name: L10n.text("TelefonX Callbacks.csv"), type: .commaSeparatedText, model: model)
    }

    static func exportCSV(_ model: PhoneModel) {
        guard model.purchases.access.permits(.contactImportExport) else { model.report(ProAccessError.required); return }
        save(Data(ContactsCSV.encode(model.snapshot.contacts).utf8),
             name: L10n.text("TelefonX Contacts.csv"), type: .commaSeparatedText, model: model)
    }
    static func importCSV(_ model: PhoneModel) {
        guard model.purchases.access.permits(.contactImportExport) else { model.report(ProAccessError.required); return }
        open(type: .commaSeparatedText, model: model) { data in
            try model.requirePro(.contactImportExport)
            guard let text = String(data: data, encoding: .utf8) else { throw ValidationError.invalidBackup }
            let contacts = try ContactsCSV.decode(text)
            var next = model.snapshot
            next.contacts += contacts
            try model.commit(next, changes: SnapshotChanges(contacts: .all))
            model.information = L10n.format("%lld contacts imported. Existing contacts were not changed.", Int64(contacts.count))
        }
    }
    static func exportBackup(_ model: PhoneModel) {
        do { save(try BackupCodec.encode(model.snapshot), name: L10n.text("TelefonX Backup.json"), type: .json, model: model) } catch { model.report(error) }
    }
    static func importBackup(_ model: PhoneModel) {
        open(type: .json, model: model) { data in
            let next = try BackupCodec.decode(data)
            guard model.activeCalls.isEmpty else { throw AppError.callInProgress }
            let alert = NSAlert(); alert.messageText = L10n.text("Replace Local Data?")
            alert.informativeText = L10n.format("This backup contains %lld lines, %lld contacts, and %lld callbacks. Current contacts, recents, callbacks, and rules will be replaced. Passwords are not imported. Export a backup first if you want to keep the current data.", Int64(next.accounts.count), Int64(next.contacts.count), Int64(next.reminders.count))
            alert.addButton(withTitle: L10n.text("Replace")); alert.addButton(withTitle: L10n.text("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            // Modal panels run a nested event loop: an incoming call or another
            // operation may have appeared since the first check.
            guard model.activeCalls.isEmpty, !model.callOperationPending, !model.configurationBusy else {
                throw AppError.callInProgress
            }
            model.configurationBusy = true
            let old = model.snapshot.accounts
            let oldReminderIDs = model.snapshot.reminders.map(\.id)
            do { try model.commit(next) }
            catch { model.configurationBusy = false; throw error }
            model.selectedAccountID = next.defaultAccountID.flatMap {
                model.permittedAccountIDs.contains($0) ? $0 : nil
            } ?? next.accounts.first?.id
            oldReminderIDs.forEach(CallReminderNotifications.remove)
            model.synchronizeReminderNotifications()
            Task {
                defer { model.configurationBusy = false }
                for account in old { try? await model.engine.unregister(account.id) }
                model.registrations.removeAll()
                for account in next.accounts { await model.register(account) }
                await model.restoreHoldMusic()
            }
        }
    }
    static func exportDiagnostics(_ model: PhoneModel) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("unknown")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let app = build.map { "TelefonX \(version) (\($0))" } ?? "TelefonX \(version)"
        let payload: [String: Any] = ["app": app, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": "arm64", "engine": "PJSIP 2.17", "ready": model.ready,
            "accounts": model.snapshot.accounts.count, "registered": model.registeredCount,
            "audioDevices": model.devices.count, "calls": model.activeCalls.map { call in
                ["state": call.phase.rawValue, "codec": call.quality?.codec ?? "unknown", "rxPackets": call.quality?.receivedPackets ?? 0,
                 "lossPercent": call.quality?.lossPercent ?? 0, "jitterMS": call.quality?.jitterMilliseconds ?? 0,
                 "srtp": call.quality?.secureMedia ?? false, "mediaError": call.mediaError] as [String: Any]
            }]
        do { save(try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]), name: "TelefonX-Diagnose.json", type: .json, model: model) }
        catch { model.report(error) }
    }
    private static func save(_ data: Data, name: String, type: UTType, model: PhoneModel) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) } catch { model.report(error) }
    }
    private static func open(type: UTType, model: PhoneModel, action: (Data) throws -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [type]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 100_000_000 else { throw ValidationError.invalidBackup }
            try action(Data(contentsOf: url))
        } catch { model.report(error) }
    }
}
