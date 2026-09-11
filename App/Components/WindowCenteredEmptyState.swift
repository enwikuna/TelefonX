import SwiftUI

/// Centers an empty state against the complete window rather than only the
/// content area below the unified toolbar.
enum WindowCenteredEmptyStateLayout {
    static let unifiedToolbarHeight: CGFloat = 52
    static let verticalOffset = -unifiedToolbarHeight / 2
}

extension View {
    func windowCenteredEmptyState() -> some View {
        offset(y: WindowCenteredEmptyStateLayout.verticalOffset)
    }
}
