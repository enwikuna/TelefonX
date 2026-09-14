import AppKit
import SwiftUI

enum TelephonyColors {
    static let call = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 29 / 255, green: 138 / 255, blue: 61 / 255, alpha: 1),
        dark: NSColor(srgbRed: 25 / 255, green: 134 / 255, blue: 54 / 255, alpha: 1)
    ))

    static let connected = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 34 / 255, green: 156 / 255, blue: 70 / 255, alpha: 1),
        dark: NSColor(srgbRed: 29 / 255, green: 168 / 255, blue: 67 / 255, alpha: 1)
    ))

    static let end = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 205 / 255, green: 55 / 255, blue: 50 / 255, alpha: 1),
        dark: NSColor(srgbRed: 215 / 255, green: 68 / 255, blue: 62 / 255, alpha: 1)
    ))

    static let failed = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 255 / 255, green: 59 / 255, blue: 48 / 255, alpha: 1),
        dark: NSColor(srgbRed: 255 / 255, green: 69 / 255, blue: 58 / 255, alpha: 1)
    ))

    static let pending = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 255 / 255, green: 149 / 255, blue: 0 / 255, alpha: 1),
        dark: NSColor(srgbRed: 255 / 255, green: 159 / 255, blue: 10 / 255, alpha: 1)
    ))

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
