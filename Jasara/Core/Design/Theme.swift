import SwiftUI
import UIKit

/// Every colour is declared once, with a light and a dark value, and is referenced
/// by name everywhere else. Task icons store the *name* (`"mint"`), never a hex
/// string, so a saved task re-renders correctly when the user flips appearance.
enum Palette: String, CaseIterable, Identifiable {
    case mint, lilac, butter, blush, sky, sand

    var id: String { rawValue }

    /// Soft fill behind an emoji or a priority section.
    var fill: Color {
        switch self {
        case .mint:   return .dynamic(light: 0xCFF3E4, dark: 0x1D4638)
        case .lilac:  return .dynamic(light: 0xE4DEFF, dark: 0x352E60)
        case .butter: return .dynamic(light: 0xFFF1BF, dark: 0x4A3F17)
        case .blush:  return .dynamic(light: 0xFFDCE3, dark: 0x522C38)
        case .sky:    return .dynamic(light: 0xD5EBFF, dark: 0x1E3B55)
        case .sand:   return .dynamic(light: 0xF1E6D6, dark: 0x43372A)
        }
    }

    /// Text or a dot drawn on top of `fill`, contrast-checked in both modes.
    var ink: Color {
        switch self {
        case .mint:   return .dynamic(light: 0x11513B, dark: 0xB6F0D8)
        case .lilac:  return .dynamic(light: 0x3E2F8F, dark: 0xD9D1FF)
        case .butter: return .dynamic(light: 0x6A5100, dark: 0xFFE9A0)
        case .blush:  return .dynamic(light: 0x8A2440, dark: 0xFFC9D5)
        case .sky:    return .dynamic(light: 0x174D7A, dark: 0xBFE0FF)
        case .sand:   return .dynamic(light: 0x5A4632, dark: 0xE6D6BF)
        }
    }

    var label: String { rawValue.capitalized }

    static func named(_ name: String) -> Palette { Palette(rawValue: name) ?? .sky }
}

enum Ink {
    static let primary   = Color.dynamic(light: 0x171A33, dark: 0xECEEF8)
    static let muted     = Color.dynamic(light: 0x565B75, dark: 0xA5AAC4)
    static let line      = Color.dynamic(light: 0xDFE2EE, dark: 0x2A2E47)
    static let surface   = Color.dynamic(light: 0xFFFFFF, dark: 0x171A2C)
    static let background = Color.dynamic(light: 0xF4F5FA, dark: 0x0F1120)
    static let accent    = Color.dynamic(light: 0x3740C4, dark: 0xAEB5FF)
    /// The dawn gradient used on the alarm ring screen and the onboarding hero.
    static let dawn = LinearGradient(
        colors: [.dynamic(light: 0xD9D2FF, dark: 0x2E2858),
                 .dynamic(light: 0xFFD6C2, dark: 0x5A3342),
                 .dynamic(light: 0xFFF0B8, dark: 0x4F4418)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    /// One colour, two values. Resolved by UIKit per trait collection so it also
    /// follows the in-app Appearance override.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Type scale. One family, weights do the work. Everything is Dynamic Type driven.
enum Face {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let sectionTitle = Font.system(.headline, design: .rounded).weight(.bold)
    static let row = Font.system(.body, design: .rounded)
    static let rowStrong = Font.system(.body, design: .rounded).weight(.semibold)
    static let caption = Font.system(.footnote, design: .rounded)
}

enum Metric {
    static let corner: CGFloat = 18
    static let rowCorner: CGFloat = 14
    static let gutter: CGFloat = 16
    /// Apple's minimum comfortable target. Grids below this size add tap tolerance.
    static let minTarget: CGFloat = 44
}
