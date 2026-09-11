import SwiftUI

struct HistoryFilterMenu: View {
    @Binding var selection: HistoryFilter

    var body: some View {
        Menu {
            Picker("Filter Recents", selection: $selection) {
                ForEach(HistoryFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.symbol).tag(filter)
                }
            }.pickerStyle(.inline).labelsHidden()
        } label: {
            Label("Filter Recents", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.visible)
        .help("\(L10n.text("Filter Recents")) · \(selection.title)")
        .accessibilityLabel("Filter Recents").accessibilityValue(selection.title)
        .accessibilityIdentifier("history-filter-menu")
    }
}
