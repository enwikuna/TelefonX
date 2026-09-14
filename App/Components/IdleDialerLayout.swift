import SwiftUI

/// Keep the keypad size fixed and scroll overflow beneath the column header.
struct IdleDialerLayout: Layout {
    let availableHeight: CGFloat

    static func topInset(availableHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        12
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: max(availableHeight, size.height + 32))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let inset = Self.topInset(availableHeight: availableHeight, contentHeight: size.height)
        content.place(at: CGPoint(x: bounds.minX, y: bounds.minY + inset), anchor: .topLeading,
                      proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}
