import SwiftUI

/// An overlay shares the cell's swipe animation without contributing to its layout.
struct ListRowSeparator: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    let visible: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if visible {
                GeometryReader { geometry in
                    let rect = HistoryRowLayout.separatorRect(
                        in: CGRect(origin: .zero, size: geometry.size), pixelHeight: 1 / displayScale)
                    Path { $0.addRect(rect) }.fill(Color(nsColor: .separatorColor))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
