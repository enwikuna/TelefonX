import SwiftUI

struct SidebarView: View {
    @Environment(PhoneModel.self) private var model
    @Binding var selection: PhoneSection?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            List(selection: $selection) {
                ForEach(PhoneSection.allCases) { item in
                    HStack {
                        Label(item.title, systemImage: item.icon)
                        Spacer()
                        let dueCount = model.pendingReminders.filter { $0.dueAt <= timeline.date }.count
                        if item == .reminders, dueCount > 0 {
                            Text("\(dueCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(L10n.format(dueCount == 1 ? "%lld Due Call Reminder" : "%lld Due Call Reminders", Int64(dueCount)))
                        }
                    }
                    .tag(item)
                    .accessibilityIdentifier("sidebar-\(item.id)")
                }
            }
            .listStyle(.sidebar)
        }
    }
}
