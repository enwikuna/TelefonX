import SwiftUI

struct Keypad: View {
    var compact = false
    let press: (String) -> Void
    private let keys = [("1", ""), ("2", "ABC"), ("3", "DEF"), ("4", "GHI"), ("5", "JKL"), ("6", "MNO"), ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"), ("*", ""), ("0", "+"), ("#", "")]
    var body: some View {
        GlassControls(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(keys, id: \.0) { key in
                    Button { press(key.0) } label: {
                        VStack(spacing: 0) {
                            Text(key.0).font(.system(size: compact ? 20 : 28, weight: .regular, design: .rounded)).monospacedDigit()
                            if !compact {
                                Text(key.1.isEmpty ? " " : key.1).font(.system(size: 8, weight: .semibold)).tracking(1.6)
                            }
                        }.frame(maxWidth: .infinity).frame(height: compact ? 36 : 52)
                    }
                    .buttonBorderShape(.roundedRectangle(radius: 13)).telefonButtonStyle()
                    .accessibilityLabel(key.0).accessibilityIdentifier("keypad-\(key.0)")
                }
            }
        }.frame(maxWidth: .infinity)
    }
}
