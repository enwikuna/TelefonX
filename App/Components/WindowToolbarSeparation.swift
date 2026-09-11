import AppKit
import SwiftUI

/// Window-wide separators would cross the sidebar. Content owns its separator.
struct WindowToolbarSeparation: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.configure() }

    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }

        func configure() {
            window?.titlebarSeparatorStyle = .none
        }
    }
}
