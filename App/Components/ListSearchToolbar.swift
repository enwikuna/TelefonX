import SwiftUI

/// A native search field that stays visible while searching or filtering existing data.
struct ListSearchToolbar: ToolbarContent {
    @Environment(PhoneModel.self) private var model
    @Binding var state: ListSearchState
    let prompt: String

    var body: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(id: "list-search-control", placement: .primaryAction) {
            searchField.glassEffect(.regular, in: .capsule)
                .padding(.trailing, trailingInset)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var trailingInset: CGFloat {
        model.snapshot.accounts.isEmpty ? 8 : 24
    }

    private var searchField: some View {
        ListSearchField(text: $state.text, prompt: prompt, visiblePrompt: "Search",
                        focusRequest: state.focusRequest,
                        onCancel: { state.clear() })
            .frame(width: ListSearchToolbarPresentation.fieldWidth, height: 36)
    }
}

/// Preserve the trailing content inset when actions are the last visible controls.
struct ListToolbarActionInset: ToolbarContent {
    @Environment(PhoneModel.self) private var model
    var body: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .primaryAction)
        if !model.snapshot.accounts.isEmpty {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
    }
}

enum ListSearchToolbarPresentation {
    static let fieldWidth: CGFloat = 180
}

extension View {
    func listToolbar<Actions: ToolbarContent>(_ title: String, subtitle: String,
        state: Binding<ListSearchState>, prompt: String, showsSearch: Bool = true, retainsActions: Bool = false,
        @ToolbarContentBuilder actions: () -> Actions) -> some View {
        toolbar {
            ListToolbarTitle(title: title, subtitle: subtitle)
            actions()
            if showsSearch { ListSearchToolbar(state: state, prompt: prompt) }
            else if retainsActions { ListToolbarActionInset() }
        }
    }
}
