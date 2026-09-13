import SwiftUI
import TelefonDomain

enum HistoryRowLayout {
    static let listContentHorizontalInset: CGFloat = 16
    // Match native swipe insets while keeping the content edge at 16 pt.
    static let selectionContentOverhang: CGFloat = 8
    static let swiftUISelectionSurfaceHorizontalInset = listContentHorizontalInset - selectionContentOverhang
    static let nativeSelectionSurfaceHorizontalInset: CGFloat = 0
    static let selectionHorizontalInset: CGFloat = 0
    static let nativeTableHorizontalInset = listContentHorizontalInset - selectionContentOverhang
    static let contentHorizontalInset = selectionContentOverhang
    static let avatarSize: CGFloat = 36
    static let avatarTextSpacing: CGFloat = 10
    static let separatorLeadingInset = contentHorizontalInset + avatarSize + avatarTextSpacing
    static let separatorTrailingInset = contentHorizontalInset
    static let selectionVerticalInset: CGFloat = 3
    static let selectionCornerRadius: CGFloat = 8

    static func separatorRect(in rowBounds: CGRect, pixelHeight: CGFloat) -> CGRect {
        let leading = rowBounds.minX + separatorLeadingInset
        let trailing = rowBounds.maxX - separatorTrailingInset
        return CGRect(x: leading, y: rowBounds.maxY - pixelHeight,
                      width: max(0, trailing - leading), height: pixelHeight)
    }
}

enum CenterColumnSectionLayout {
    static let height: CGFloat = 34
    static let titleBottomInset: CGFloat = 5
    static let interSectionSpacing: CGFloat = 16
}

struct HistoryRow: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.locale) private var locale
    let record: CallRecord
    let now: Date
    let selected: Bool
    let selectionCount: Int
    let requestAction: (HistoryActionRequest) -> Void
    let editContact: (PhoneContact) -> Void
    let addToContact: (CallRecord) -> Void
    let scheduleReminder: (CallRecord) -> Void
    let deleteSelection: () -> Void
    private var hasDestination: Bool { (try? CallDestination(record.remote)) != nil }
    private var blockedSymbol: String? {
        HistoryPresentation.blockedSymbol(for: record.remote, rules: model.snapshot.blocks)
    }
    private var isBlocked: Bool { blockedSymbol != nil }

    var body: some View {
        HStack(spacing: HistoryRowLayout.avatarTextSpacing) {
            ContactAvatar(contact: model.displayContact(for: record.remote))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(model.displayName(record.remote)).font(.body.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(record.outcome == .missed ? .red : .primary)
                    if let blockedSymbol {
                        Image(systemName: blockedSymbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .fixedSize()
                            .accessibilityLabel("Blocked")
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: record.incoming ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(record.outcome == .missed ? .red : .secondary)
                        .frame(width: 10)
                        .accessibilityLabel(record.incoming ? "Incoming Call" : "Outgoing Call")
                    Text(HistoryPresentation.secondaryText(record, displayName: model.displayName(record.remote)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(HistoryPresentation.timestamp(record.startedAt, relativeTo: now, locale: locale))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize()
                .help(record.startedAt.formatted(date: .complete, time: .shortened))
            HistoryRowActions(name: model.displayName(record.remote), hasDestination: hasDestination,
                              startsConsultation: !model.activeCalls.isEmpty,
                              startsCallImmediately: model.automaticallyStartListCalls,
                              prepareCall: prepareCall)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, HistoryRowLayout.contentHorizontalInset)
        .frame(height: HistoryTable.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: HistoryRowLayout.selectionCornerRadius)
                    .fill(Color.primary.opacity(0.08))
                    .padding(.horizontal, HistoryRowLayout.selectionHorizontalInset)
                    .padding(.vertical, HistoryRowLayout.selectionVerticalInset)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, HistoryRowLayout.nativeSelectionSurfaceHorizontalInset)
        .contextMenu {
            if selected && selectionCount > 1 {
                Button("Delete \(selectionCount) Calls …", systemImage: "trash", role: .destructive,
                       action: deleteSelection)
            } else {
                HistoryContextMenu(record: record, hasDestination: hasDestination, isBlocked: isBlocked,
                                   editContact: editContact, addToContact: { addToContact(record) },
                                   scheduleReminder: { scheduleReminder(record) },
                                   toggleBlock: { requestAction(.init(kind: isBlocked ? .unblock : .block, record: record)) },
                                   delete: { requestAction(.init(kind: .delete, record: record)) })
            }
        }
    }

    private func prepareCall() {
        let accountID = model.snapshot.accounts.contains(where: { $0.id == record.accountID }) ? record.accountID : nil
        Task { await model.performListCall(record.remote, preferredAccountID: accountID) }
    }
}
