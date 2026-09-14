import SwiftUI

// Auxiliary-window appearance only. The main window uses its existing layout.
extension View {
    @ViewBuilder func hiddenWindowToolbarBackgroundOnMacOS27() -> some View {
        if #available(macOS 27.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }

    @ViewBuilder func settingsWindowToolbarAppearanceOnMacOS27() -> some View {
        if #available(macOS 27.0, *) {
            toolbarBackground(.bar, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            self
        }
    }
}
