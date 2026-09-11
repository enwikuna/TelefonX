import TelefonDomain

struct HistoryActionRequest: Identifiable {
    enum Kind: String { case block, unblock, delete }
    let kind: Kind
    let records: [CallRecord]

    init(kind: Kind, record: CallRecord) {
        self.kind = kind
        records = [record]
    }

    init(deleting records: [CallRecord]) {
        kind = .delete
        self.records = records
    }

    var record: CallRecord { records[0] }
    var id: String { "\(kind.rawValue)-\(records.map(\.id.uuidString).sorted().joined(separator: ","))" }
    var title: String {
        switch kind {
        case .block: L10n.text("Block Number?")
        case .unblock: L10n.text("Unblock Number?")
        case .delete: records.count == 1 ? L10n.text("Delete Call?") : L10n.format("Delete %lld Calls?", Int64(records.count))
        }
    }
    var button: String {
        switch kind {
        case .block: L10n.text("Block Number")
        case .unblock: L10n.text("Unblock")
        case .delete: records.count == 1 ? L10n.text("Delete") : L10n.format("Delete %lld", Int64(records.count))
        }
    }
    var message: String {
        switch kind {
        case .delete:
            records.count == 1
                ? L10n.text("Only this entry will be removed from local recents. The contact and other calls remain. A previously exported backup can restore the entry.")
                : L10n.format("Only these %lld entries will be removed from local recents. Contacts and other calls remain. A previously exported backup can restore the entries.", Int64(records.count))
        case .block:
            L10n.format("Future calls from %@ will be rejected on every line. Other numbers for this contact remain reachable. You can remove the block under Settings → Rules.", record.remote)
        case .unblock:
            L10n.format("Future calls from %@ will be allowed again. The entry remains in Recents.", record.remote)
        }
    }
}
