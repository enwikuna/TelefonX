import SwiftUI

enum ActionEmphasis { case regular, prominent }

/// Shared glass styling for app actions. Native toolbars retain their own surfaces.
extension View {
    @ViewBuilder func telefonButtonStyle(_ emphasis: ActionEmphasis = .regular) -> some View {
        switch emphasis {
        case .regular: buttonStyle(.glass)
        case .prominent: buttonStyle(.glassProminent)
        }
    }

    /// Gives a button-like Menu the same 36-point circular footprint as the
    /// row action Buttons while retaining the native dropdown interaction.
    @ViewBuilder func telefonRowActionMenuStyle() -> some View {
        menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: RowActionIcon.controlSize, height: RowActionIcon.controlSize)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

struct GlassControls<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content
    var body: some View {
        GlassEffectContainer(spacing: spacing, content: content)
    }
}
