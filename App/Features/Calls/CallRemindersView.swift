import SwiftUI
import TelefonDomain

struct CallRemindersView: View {
    @Environment(PhoneModel.self) private var model
    @Binding var searchState: ListSearchState
    @State private var selection: Set<UUID> = []
    @State private var creating: CallReminder?
    @State private var editing: CallReminder?
    @State private var deleting: Set<UUID> = []

    private var visible: [CallReminder] {
        let query = searchState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.snapshot.reminders.filter { reminder in
            query.isEmpty || [reminder.name, reminder.number, reminder.note].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var body: some View {
        Group {
            if model.canUseReminders {
                reminderList
            } else {
                ContentUnavailableView {
                    Label("Callbacks with TelefonX Pro", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Plan callbacks with dates, notes, and reminders. Your saved callbacks are retained and can be exported.")
                } actions: {
                    VStack(spacing: 10) {
                        ProAccessButton()
                            .telefonButtonStyle(.prominent)
                        if !model.snapshot.reminders.isEmpty {
                            Button("Export Saved Callbacks …") { FileActions.exportRemindersCSV(model) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .listToolbarTitle("Call Reminders", subtitle: L10n.text("TelefonX Pro"))
            }
        }
        .onChange(of: model.canUseReminders) { _, available in
            if !available { creating = nil; editing = nil; deleting = []; selection = [] }
        }
    }

    private var reminderList: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            CallReminderTable(sections: sections(now: timeline.date),
                              selection: $selection, content: { reminder, selected in
                AnyView(CallReminderRow(reminder: reminder, now: timeline.date, selected: selected,
                                        prepareCall: { Task { await model.performReminderListAction(reminder.id) } },
                                        toggleCompleted: { toggleCompleted(reminder) })
                    .environment(model)
                    .contextMenu { reminderMenu(reminder) })
            }, edit: { editing = $0 }, delete: { deleting = $0 }, complete: { ids in
                do { try model.completeReminders(ids) } catch { model.report(error) }
            })
            .ignoresSafeArea(.container, edges: .top)
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView {
                        Label(searchState.text.isEmpty ? "No Call Reminders" : "No Results",
                              systemImage: "calendar.badge.clock")
                    } description: {
                        Text(searchState.text.isEmpty
                             ? "Scheduled callbacks appear here."
                             : "Try another name, number, or note.")
                    }
                    .windowCenteredEmptyState()
                    .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: visible.map(\.id)) { _, ids in selection.formIntersection(ids) }
        .navigationSubtitle(countText)
        .toolbarBackgroundVisibility(visible.isEmpty && model.snapshot.accounts.isEmpty ? .hidden : .automatic,
                                     for: .windowToolbar)
        .listToolbar("Call Reminders", subtitle: countText,
                     state: $searchState, prompt: "Search Call Reminders",
                     showsSearch: !model.snapshot.reminders.isEmpty, retainsActions: true) {
            ToolbarItem(id: "reminder-add", placement: .primaryAction) {
                Button {
                    creating = CallReminder(name: "", number: "", dueAt: Date().addingTimeInterval(3600),
                                            accountID: model.selectedAccountID)
                } label: {
                    Label("Schedule Callback …", systemImage: "plus").labelStyle(.iconOnly)
                }
                .help("Schedule Callback …")
                .accessibilityIdentifier("reminder-add")
            }
        }
        .sheet(item: $creating) {
            CallReminderEditor(reminder: $0, isNew: true, allowsEditingRecipient: true)
        }
        .sheet(item: $editing) { CallReminderEditor(reminder: $0, isNew: false) }
        .alert(deleting.count == 1 ? L10n.text("Delete Callback?") : L10n.format("Delete %lld Callbacks?", Int64(deleting.count)),
               isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } }),
               presenting: deleting) { ids in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do { try model.deleteReminders(ids) } catch { model.report(error) }
                deleting = []
            }
        } message: { ids in
            Text(ids.count == 1
                 ? "The callback reminder will be permanently removed. Contacts and recents are retained."
                 : "The selected callback reminders will be permanently removed. Contacts and recents are retained.")
        }
    }

    private var pending: [CallReminder] {
        visible.filter { $0.completedAt == nil }.sorted { $0.dueAt < $1.dueAt }
    }
    private var completed: [CallReminder] {
        visible.filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    private var countText: String {
        L10n.format(pending.count == 1 ? "%lld Open Call Reminder" : "%lld Open Call Reminders", Int64(pending.count))
    }

    private func sections(now: Date) -> [CallReminderTableSection] {
        [
            .init(title: "Overdue", reminders: pending.filter { $0.dueAt <= now }),
            .init(title: "Today", reminders: pending.filter { $0.dueAt > now && Calendar.current.isDateInToday($0.dueAt) }),
            .init(title: "Later", reminders: pending.filter { $0.dueAt > now && !Calendar.current.isDateInToday($0.dueAt) }),
            .init(title: "Done", reminders: completed)
        ]
    }

    @ViewBuilder private func reminderMenu(_ reminder: CallReminder) -> some View {
        let ids = CallReminderSelection.contextTargets(clicked: reminder.id, selected: selection,
                                                       visible: Set(visible.map(\.id)))
        if ids.count > 1 {
            let openCount = visible.filter { ids.contains($0.id) && $0.completedAt == nil }.count
            Button(L10n.format(openCount == 1 ? "Mark %lld Callback as Done" : "Mark %lld Callbacks as Done",
                               Int64(openCount)), systemImage: "checkmark.circle") {
                do { try model.completeReminders(ids) } catch { model.report(error) }
            }
            .disabled(openCount == 0)
            Divider()
            Button(L10n.format("Delete %lld Callbacks …", Int64(ids.count)), systemImage: "trash", role: .destructive) { deleting = ids }
        } else {
            Button("Place Call", systemImage: "phone") {
                Task { await model.callReminderNow(reminder.id) }
            }
            .disabled(!model.canCallReminder(reminder))
            Button("Edit …", systemImage: "pencil") { editing = reminder }
            Button(reminder.completedAt == nil ? "Mark as Done" : "Reopen",
                   systemImage: reminder.completedAt == nil ? "checkmark.circle" : "arrow.uturn.backward") {
                toggleCompleted(reminder)
            }
            if reminder.completedAt == nil {
                Button("10 Minutes Later", systemImage: "clock.arrow.circlepath") {
                    do { try model.snoozeReminder(reminder.id) } catch { model.report(error) }
                }
            }
            Divider()
            Button("Delete …", systemImage: "trash", role: .destructive) { deleting = [reminder.id] }
        }
    }

    private func toggleCompleted(_ reminder: CallReminder) {
        do { try model.completeReminder(reminder.id, completed: reminder.completedAt == nil) }
        catch { model.report(error) }
    }

}

enum CallReminderRowPresentation {
    static func showsPendingActions(completedAt: Date?) -> Bool {
        completedAt == nil
    }
}

private enum CallReminderListLayout {
    static let contentHorizontalInset = HistoryRowLayout.contentHorizontalInset
    static let statusWidth = HistoryRowLayout.avatarSize
    static let statusTextSpacing = HistoryRowLayout.avatarTextSpacing
}


private struct CallReminderRow: View {
    @Environment(PhoneModel.self) private var model
    let reminder: CallReminder
    let now: Date
    let selected: Bool
    let prepareCall: () -> Void
    let toggleCompleted: () -> Void

    var body: some View {
        HStack(spacing: CallReminderListLayout.statusTextSpacing) {
            Button(action: toggleCompleted) {
                Image(systemName: reminder.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(iconColor)
                    .frame(width: CallReminderListLayout.statusWidth)
            }
            .buttonStyle(.plain)
            .help(reminder.completedAt == nil ? "Mark as Done" : "Reopen")
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.name).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Text(reminder.number).lineLimit(1)
                    if !reminder.note.isEmpty {
                        Text("·")
                        Text(reminder.note).lineLimit(1)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if CallReminderRowPresentation.showsPendingActions(completedAt: reminder.completedAt) {
                Text(dueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(iconColor)
                    .fixedSize()
                Button(action: prepareCall) { RowActionIcon(systemName: "phone.fill") }
                    .telefonButtonStyle().buttonBorderShape(.circle)
                    .help(model.activeCalls.isEmpty ? "Use Number for Callback" : "Start Consultation")
                    .accessibilityLabel(model.activeCalls.isEmpty
                                        ? L10n.format("Use %@ for Callback", reminder.name)
                                        : L10n.format("Start Consultation with %@", reminder.name))
            }
        }
        .padding(.horizontal, CallReminderListLayout.contentHorizontalInset)
        .frame(maxWidth: .infinity, minHeight: HistoryTable.rowHeight,
               maxHeight: HistoryTable.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: HistoryRowLayout.selectionCornerRadius)
                    .fill(Color.primary.opacity(0.08))
                    .padding(.vertical, HistoryRowLayout.selectionVerticalInset)
            }
        }
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        if reminder.completedAt != nil { return .secondary }
        return reminder.dueAt <= now ? .red : .secondary
    }
    private var dueText: String {
        if Calendar.current.isDateInToday(reminder.dueAt) {
            return reminder.dueAt.formatted(date: .omitted, time: .shortened)
        }
        return reminder.dueAt.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Right-clicking a selected row acts on the visible selection; an unselected row acts alone.
enum CallReminderSelection {
    static func contextTargets(clicked: UUID, selected: Set<UUID>, visible: Set<UUID>) -> Set<UUID> {
        guard visible.contains(clicked) else { return [] }
        return selected.contains(clicked) ? selected.intersection(visible) : [clicked]
    }
}
