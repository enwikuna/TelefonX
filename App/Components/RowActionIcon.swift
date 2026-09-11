import SwiftUI

struct RowActionIcon: View {
    @Environment(\.isEnabled) private var isEnabled

    static let symbolSize: CGFloat = 16
    static let frameSize: CGFloat = 28
    static let controlSize: CGFloat = 36
    let systemName: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: Self.symbolSize, weight: systemName == "phone.fill" ? .regular : .semibold))
            .foregroundStyle(isEnabled ? tint : Color.secondary)
            .frame(width: Self.frameSize, height: Self.frameSize)
    }
}
