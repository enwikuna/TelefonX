import AppKit
import Testing
@testable import TelefonX

@Suite @MainActor struct FixedSidebarTests {
    @Test func attachmentLocksOnlyTheContainingSidebar() {
        _ = NSApplication.shared
        let sidebarController = NSViewController()
        sidebarController.view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 640))
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        let detailController = NSViewController()
        detailController.view = NSView()
        let detail = NSSplitViewItem(viewController: detailController)
        detail.minimumThickness = 480
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(detail)
        let window = NSWindow(contentViewController: split)
        defer { window.close() }

        let probe = FixedSidebarConfiguration.Probe(width: 220)
        sidebarController.view.addSubview(probe)
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(!sidebar.canCollapse)
        #expect(!sidebar.canCollapseFromWindowResize)
        #expect(sidebar.minimumThickness == 220)
        #expect(sidebar.maximumThickness == 220)
        #expect(detail.minimumThickness == 480)

        // SwiftUI can reapply its sidebar defaults after attaching the hosting view.
        sidebar.canCollapse = true
        sidebar.canCollapseFromWindowResize = true
        #expect(!sidebar.canCollapse)
        #expect(!sidebar.canCollapseFromWindowResize)

        // Reattaching the bridge must also configure a newly created native item.
        probe.removeFromSuperview()
        sidebar.canCollapse = true
        sidebar.minimumThickness = 190
        sidebar.maximumThickness = 280
        sidebarController.view.addSubview(probe)
        #expect(!sidebar.canCollapse)
        #expect(sidebar.minimumThickness == sidebar.maximumThickness)
    }
}
