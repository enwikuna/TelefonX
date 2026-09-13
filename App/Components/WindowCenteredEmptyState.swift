import SwiftUI

/// Centers an empty state against the complete window rather than only the
/// content area below the unified toolbar.
enum WindowCenteredEmptyStateLayout {
    static let unifiedToolbarHeight: CGFloat = 52
    static let verticalOffset = -unifiedToolbarHeight / 2
}

extension View {
    /// Keep native toolbar scroll tracking alive while the screen has no rows.
    func scrollableEmptyState() -> some View {
        GeometryReader { geometry in
            ScrollView {
                self
                    .padding(.top, WindowCenteredEmptyStateLayout.unifiedToolbarHeight)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    func windowCenteredEmptyState() -> some View {
        offset(y: WindowCenteredEmptyStateLayout.verticalOffset)
    }
}
