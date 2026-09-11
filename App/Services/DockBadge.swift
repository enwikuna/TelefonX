import AppKit

@MainActor enum DockBadge {
    static func update(missedCallCount: Int) {
        guard !PreviewSupport.enabled else { return }
        NSApp.dockTile.badgeLabel = missedCallCount > 0 ? String(missedCallCount) : nil
    }
}
