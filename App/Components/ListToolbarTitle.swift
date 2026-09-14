import SwiftUI

struct ListToolbarTitle: ToolbarContent {
    static let contentAlignmentOffset: CGFloat = 8
    let title: String
    let subtitle: String

    var body: some ToolbarContent {
        ToolbarItem(id: "list-title", placement: .primaryAction) { label }
            .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible, placement: .primaryAction)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text(title)).font(.headline)
            Text(subtitle).secondaryContextLabelStyle()
        }
        .padding(.leading, Self.contentAlignmentOffset)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("list-toolbar-title")
    }
}

extension View {
    func secondaryContextLabelStyle() -> some View {
        font(.caption2).foregroundStyle(.secondary)
    }
}

extension View {
    func listToolbarTitle(_ title: String, subtitle: String) -> some View {
        toolbar { ListToolbarTitle(title: title, subtitle: subtitle) }
    }
}
