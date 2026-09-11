import AppKit
import SwiftUI

/// SwiftUI exposes sidebar width preferences, but not NSSplitViewItem.canCollapse.
/// Configure only the containing native sidebar, without delegates or resize callbacks.
struct FixedSidebarConfiguration: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> Probe { Probe(width: width) }

    func updateNSView(_ view: Probe, context: Context) {
        view.width = width
        view.configureSidebar()
    }

    final class Probe: NSView {
        var width: CGFloat
        private weak var configuredSidebar: NSSplitViewItem?
        private var collapseObservation: NSKeyValueObservation?
        private var windowCollapseObservation: NSKeyValueObservation?

        init(width: CGFloat) {
            self.width = width
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureSidebar()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureSidebar()
        }

        func configureSidebar() {
            var ancestor = superview
            while let view = ancestor {
                if let split = view as? NSSplitView,
                   let controller = split.delegate as? NSSplitViewController,
                   let sidebar = controller.splitViewItems.first(where: {
                       self.isDescendant(of: $0.viewController.view)
                   }) {
                    if configuredSidebar !== sidebar {
                        configuredSidebar = sidebar
                        // SwiftUI reapplies its default collapsing policy after attachment.
                        // Preserve the fixed policy when that public AppKit property changes.
                        collapseObservation = sidebar.observe(\.canCollapse, options: [.new]) { [weak self] _, change in
                            guard change.newValue == true else { return }
                            MainActor.assumeIsolated { self?.configuredSidebar?.canCollapse = false }
                        }
                        windowCollapseObservation = sidebar.observe(\.canCollapseFromWindowResize, options: [.new]) { [weak self] _, change in
                            guard change.newValue == true else { return }
                            MainActor.assumeIsolated { self?.configuredSidebar?.canCollapseFromWindowResize = false }
                        }
                    }
                    sidebar.canCollapse = false
                    sidebar.canCollapseFromWindowResize = false
                    sidebar.minimumThickness = width
                    sidebar.maximumThickness = width
                    if sidebar.isCollapsed { sidebar.isCollapsed = false }
                    return
                }
                ancestor = view.superview
            }
            collapseObservation = nil
            windowCollapseObservation = nil
            configuredSidebar = nil
        }
    }
}
