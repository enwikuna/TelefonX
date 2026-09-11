import SwiftUI
import TelefonDomain

struct CallReminderEditor: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: CallReminder
    @State private var error: String?
    private let earliestDueDate: Date
    private let isNew: Bool
    private let allowsEditingRecipient: Bool

    init(reminder: CallReminder, isNew: Bool, allowsEditingRecipient: Bool = false) {
        _reminder = State(initialValue: reminder)
        earliestDueDate = Date().addingTimeInterval(60)
        self.isNew = isNew
        self.allowsEditingRecipient = allowsEditingRecipient
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "Schedule Callback" : "Edit Callback")
                        .font(.title2.weight(.semibold))
                    if !allowsEditingRecipient { Text(reminder.name).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(22)

            Form {
                if allowsEditingRecipient {
                    TextField("Name", text: $reminder.name)
                        .accessibilityIdentifier("reminder-name")
                    TextField("Phone Number or SIP Address", text: $reminder.number)
                        .accessibilityIdentifier("reminder-number")
                } else {
                    LabeledContent("Phone Number") { Text(reminder.number).textSelection(.enabled) }
                }
                DatePicker("Remind Me", selection: $reminder.dueAt, in: earliestDueDate...,
                           displayedComponents: [.date, .hourAndMinute])
                LabeledContent("Quick Selection") {
                    Menu("Choose Time") {
                        Button("In 1 Hour") { setDue(hours: 1) }
                        Button("In 2 Hours") { setDue(hours: 2) }
                        Button("Tomorrow") { setDayOffset(1, hour: 9) }
                        Button("In 2 Days") { setDayOffset(2, hour: 9) }
                        Button("Next Week") { setDayOffset(7, hour: 9) }
                    }
                }
                Picker("Line", selection: $reminder.accountID) {
                    Text("Current Selection").tag(UUID?.none)
                    ForEach(model.snapshot.accounts) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Notification", selection: $reminder.notificationTiming) {
                    Text(L10n.format("Default (%@)", model.defaultReminderNotificationTiming.localizedTitle))
                        .tag(CallReminderNotificationTiming?.none)
                    ForEach(CallReminderNotificationTiming.allCases, id: \.self) { timing in
                        Text(timing.localizedTitle).tag(Optional(timing))
                    }
                }
                Section("Note") {
                    NativeNotesEditor(text: $reminder.note)
                        .frame(minHeight: 105, idealHeight: 120, maxHeight: 145)
                }
            }
            .formStyle(.grouped)

            if hasInvalidDueDate {
                Text("Choose a Time in the Future.")
                    .font(.callout).foregroundStyle(.red).padding(.horizontal, 22)
            } else if let error {
                Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal, 22)
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    reminder.note = reminder.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        if allowsEditingRecipient {
                            reminder.number = try CallDestination(reminder.number).value
                            reminder.name = reminder.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if reminder.name.isEmpty { reminder.name = reminder.number }
                        }
                        try model.saveReminder(reminder)
                        dismiss()
                    }
                    catch { self.error = L10n.error(error) }
                }
                .keyboardShortcut(.defaultAction)
                .telefonButtonStyle(.prominent)
                .disabled(hasInvalidDueDate || (allowsEditingRecipient && (try? CallDestination(reminder.number)) == nil))
            }
            .padding(20)
        }
        .frame(width: 500, height: allowsEditingRecipient ? 620 : 580)
        .telefonButtonStyle()
    }

    private func setDue(hours: Int) { reminder.dueAt = Date().addingTimeInterval(Double(hours) * 3600) }

    private var hasInvalidDueDate: Bool {
        reminder.completedAt == nil && reminder.dueAt <= Date()
    }

    private func setDayOffset(_ days: Int, hour: Int) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        reminder.dueAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}
