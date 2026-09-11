import AppKit
import SwiftUI
import TelefonDomain

struct HistoryView: View {
    @Environment(PhoneModel.self) private var model
    @Binding var searchState: ListSearchState
    private var search: String { searchState.text }
    var showFavorites: () -> Void = {}
    @State private var filter: HistoryFilter = .all
    @State private var selectedRecords: Set<UUID> = []
    @State private var actionRequest: HistoryActionRequest?
    @State private var editingContact: PhoneContact?
    @State private var addingNumber: CallRecord?
    @State private var editingReminder: CallReminder?
    @State private var dismissedEndedCallID: UUID?
    @AppStorage("history.hideBlockedInAll") private var hideBlockedInAll = false
    private var records: [CallRecord] {
        HistoryPresentation.records(model.snapshot.history, filter: filter, hideBlockedInAll: hideBlockedInAll,
                                    search: search, displayName: model.displayName)
    }
    var body: some View {
        let records = records
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let table = HistoryTable(model: model, records: records, now: timeline.date, selection: $selectedRecords,
                                     requestAction: { actionRequest = $0 }, editContact: { editingContact = $0 },
                                     addToContact: { addingNumber = $0 },
                                     scheduleReminder: { editingReminder = model.reminderDraft(for: $0) })
            NativeHistoryWorkspace(table: table,
                header: showsPinnedHeader ? AnyView(pinnedHeader.environment(model)) : nil)
                .ignoresSafeArea(.container, edges: .top)
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? filter.emptyTitle : L10n.text("No Results"),
                              systemImage: filter == .missed ? "phone.badge.checkmark" : "clock")
                    } description: {
                        Text(search.isEmpty ? "Your call history appears here across all lines." : "Try another name or number.")
                    }
                    .windowCenteredEmptyState()
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationSubtitle(countText)
        .listToolbar("Recents", subtitle: countText, state: $searchState, prompt: "Search Calls",
                     showsSearch: !model.snapshot.history.isEmpty) {
            if !model.snapshot.history.isEmpty {
                ToolbarItem(id: "history-filter", placement: .primaryAction) {
                    HistoryFilterMenu(selection: $filter)
                }
            }
        }
        // Presentations belong to the screen, not to recycled table cells.
        .sheet(item: $editingContact) { ContactEditor(contact: $0) }
        .sheet(item: $addingNumber) { AddNumberToContact(number: $0.remote) }
        .sheet(item: $editingReminder) { CallReminderEditor(reminder: $0, isNew: true) }
        .onChange(of: model.canUseReminders) { _, available in
            if !available { editingReminder = nil }
        }
        .onChange(of: records.map(\.id)) { _, ids in
            selectedRecords.formIntersection(ids)
        }
        .onAppear { markMissedCallsSeenIfVisible() }
        .onChange(of: model.missedCallBadgeCount) { _, _ in markMissedCallsSeenIfVisible() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.markMissedCallsSeen()
        }
        .task(id: PublicCallerLookupRequest(enabled: model.canUsePublicCallerLookup,
                                            numbers: records.map(\.remote))) {
            guard model.canUsePublicCallerLookup else { return }
            await model.resolvePublicCallerNames(records.map(\.remote))
        }
        .alert(actionRequest?.title ?? "Recents",
               isPresented: Binding(get: { actionRequest != nil }, set: { if !$0 { actionRequest = nil } }),
               presenting: actionRequest) { request in
            Button("Cancel", role: .cancel) { }
            Button(request.button, role: request.kind == .unblock ? nil : .destructive) {
                switch request.kind {
                case .block: model.block(request.record.remote)
                case .unblock: model.unblock(request.record.remote)
                case .delete:
                    do { try model.deleteHistoryRecords(Set(request.records.map(\.id))) }
                    catch { model.report(error) }
                }
            }
        } message: { request in Text(request.message) }
    }

    private var showsPinnedHeader: Bool {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!ContactFavorites.ordered(model.snapshot.contacts).isEmpty || endedCallSuggestion != nil)
    }

    @ViewBuilder private var pinnedHeader: some View {
        if showsPinnedHeader {
            VStack(spacing: 0) {
                FavoritesStrip(showAll: showFavorites)
                if let record = endedCallSuggestion {
                    EndedCallReminderSuggestion(name: model.displayName(record.remote),
                                                schedule: { editingReminder = model.reminderDraft(for: record) },
                                                dismiss: { dismissedEndedCallID = record.id })
                        .id(record.id)
                }
            }
        }
    }

    private var countText: String {
        L10n.format(records.count == 1 ? "%lld Call" : "%lld Calls", Int64(records.count))
    }

    private func markMissedCallsSeenIfVisible() {
        guard NSApp.isActive else { return }
        model.markMissedCallsSeen()
    }

    private var endedCallSuggestion: CallRecord? {
        guard model.canUseReminders, let record = model.lastEndedCall, record.outcome == .answered,
              dismissedEndedCallID != record.id,
              !model.snapshot.reminders.contains(where: { $0.sourceCallID == record.id }) else { return nil }
        return record
    }
}

private struct EndedCallReminderSuggestion: View {
    private enum FocusedAction: Hashable { case schedule, dismiss }

    let name: String
    let schedule: () -> Void
    let dismiss: () -> Void
    @State private var remainingLifetime = EndedCallSuggestionTimeout.duration
    @State private var isHovered = false
    @FocusState private var focusedAction: FocusedAction?

    private var isPaused: Bool { isHovered || focusedAction != nil }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
            Text("Call with \(name) ended").font(.callout).lineLimit(1)
            Spacer()
            Button("Schedule Callback …", action: schedule).telefonButtonStyle()
                .focused($focusedAction, equals: .schedule)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Dismiss").accessibilityLabel("Dismiss")
                .focused($focusedAction, equals: .dismiss)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .onHover { isHovered = $0 }
        .task(id: isPaused) {
            guard !isPaused, remainingLifetime > 0 else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            do {
                try await Task.sleep(for: .seconds(remainingLifetime))
                dismiss()
            } catch {
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                remainingLifetime = EndedCallSuggestionTimeout.remaining(remainingLifetime, after: elapsed)
            }
        }
    }
}

enum EndedCallSuggestionTimeout {
    static let duration: TimeInterval = 60

    static func remaining(_ remaining: TimeInterval, after elapsed: TimeInterval) -> TimeInterval {
        max(0, remaining - max(0, elapsed))
    }
}

private struct PublicCallerLookupRequest: Hashable {
    let enabled: Bool
    let numbers: [String]
}
