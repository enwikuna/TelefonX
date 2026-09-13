import AppKit
import SwiftUI

/// AppKit positions the fixed header and supplies its inset to the scrolling content.
struct NativeHistoryWorkspace: NSViewControllerRepresentable {
    let table: HistoryTable
    let header: AnyView?

    func makeCoordinator() -> HistoryTable.Coordinator { table.makeCoordinator() }

    func makeNSViewController(context: Context) -> Controller {
        Controller(scroll: HistoryTable.makeScrollView(coordinator: context.coordinator,
                                                      scroll: HeaderFadeScrollView()))
    }

    func updateNSViewController(_ controller: Controller, context: Context) {
        context.coordinator.update(table)
        controller.setHeader(header)
    }

    static func dismantleNSViewController(_ controller: Controller, coordinator: HistoryTable.Coordinator) {
        HistoryTable.dismantleNSView(controller.scroll, coordinator: coordinator)
    }

    final class Controller: NSSplitViewController {
        let scroll: NSScrollView
        private let content = NSViewController()
        private let accessory = NSSplitViewItemAccessoryViewController()
        private let headerView = NSHostingView(rootView: AnyView(EmptyView()))
        private var item: NSSplitViewItem!

        init(scroll: NSScrollView) {
            self.scroll = scroll
            super.init(nibName: nil, bundle: nil)
            content.view = scroll
            item = NSSplitViewItem(viewController: content)
            item.automaticallyAdjustsSafeAreaInsets = true
            addSplitViewItem(item)
            accessory.automaticallyAppliesContentInsets = false
            if #available(macOS 26.1, *) { accessory.preferredScrollEdgeEffectStyle = .soft }
            headerView.sizingOptions = [.intrinsicContentSize]
            accessory.view = headerView
        }

        required init?(coder: NSCoder) { nil }

        func setHeader(_ header: AnyView?) {
            if let header {
                headerView.rootView = header
                if item.topAlignedAccessoryViewControllers.isEmpty {
                    item.addTopAlignedAccessoryViewController(accessory)
                }
            } else if !item.topAlignedAccessoryViewControllers.isEmpty {
                item.removeTopAlignedAccessoryViewController(at: 0)
            }
            updateFade()
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            updateFade()
        }

        private func updateFade() {
            (scroll as? HeaderFadeScrollView)?.fadeHeight =
                item.topAlignedAccessoryViewControllers.isEmpty ? nil : 72
        }
    }
}

/// Fade only the scrolling content, leaving the fixed favorites and window surface intact.
final class HeaderFadeScrollView: InsetListScrollView {
    var fadeHeight: CGFloat? { didSet { updateFade() } }
    private let fade = CAGradientLayer()

    override func tile() {
        super.tile()
        updateFade()
    }

    private func updateFade() {
        // The clip view's bounds move with every scroll event. Mask the fixed
        // scroll viewport instead so a fast scroll cannot outrun the fade by a frame.
        contentView.layer?.mask = nil
        guard let fadeHeight, fadeHeight > 0, bounds.height > 0 else {
            layer?.mask = nil
            return
        }
        wantsLayer = true
        let height = bounds.height
        let boundary = min(height, max(0, contentInsets.top))
        let visibleEnd = max(0, (height - boundary - 4) / height)
        func location(_ progress: CGFloat) -> NSNumber {
            NSNumber(value: min(1, (height - boundary + fadeHeight * progress) / height))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = layer?.bounds ?? bounds
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor,
                       NSColor.black.withAlphaComponent(0.42).cgColor,
                       NSColor.black.withAlphaComponent(0.14).cgColor,
                       NSColor.black.withAlphaComponent(0.03).cgColor,
                       NSColor.clear.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: visibleEnd), location(1.0 / 6),
                          location(0.36), location(2.0 / 3), location(1), 1]
        layer?.mask = fade
        CATransaction.commit()
    }
}
