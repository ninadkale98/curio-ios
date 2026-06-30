import SwiftUI
import CoreText
import UIKit

// MARK: - Color Hex Init
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Palette
// Keyed on isDark. App currently forces dark; light kept for future toggle.
struct Palette {
    let pageBg: Color
    let surface: Color
    let elevated: Color   // raised elements: chips, tables, diagrams
    let text: Color
    let sub: Color
    let faint: Color
    let line: Color
    let chip: Color
    let icon: Color
    let accent: Color

    static let dark = Palette(
        pageBg:   Color(hex: "#08090B"),
        surface:  Color(hex: "#101216"),
        elevated: Color(hex: "#1A1D23"),
        text:     Color(hex: "#F4F5F6"),
        sub:      Color.white.opacity(0.62),
        faint:    Color.white.opacity(0.38),
        line:     Color.white.opacity(0.09),
        chip:     Color.white.opacity(0.07),
        icon:     Color.white.opacity(0.85),
        accent:   Color(hex: "#6AA0FF")
    )

    static let light = Palette(
        pageBg:   Color(hex: "#E9EAEC"),
        surface:  Color(hex: "#FFFFFF"),
        elevated: Color(hex: "#F3F4F6"),
        text:     Color(hex: "#0B0C0E"),
        sub:      Color(hex: "#565A61"),
        faint:    Color(hex: "#9A9EA5"),
        line:     Color.black.opacity(0.08),
        chip:     Color.black.opacity(0.05),
        icon:     Color(hex: "#2A2D33"),
        accent:   Color(hex: "#2F64D8")
    )
}

// MARK: - Theme Environment Key
struct ThemeKey: EnvironmentKey {
    static let defaultValue: Palette = .dark
}

extension EnvironmentValues {
    var theme: Palette {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Font Registration
// Fonts ship in the bundle's Fonts/ folder and are registered at launch so
// Font.custom resolves them. Silent system fallback if a file is missing.
enum AppFonts {
    static let displayHeavy   = "SchibstedGrotesk-ExtraBold"
    static let displayBold    = "SchibstedGrotesk-Bold"
    static let displaySemi    = "SchibstedGrotesk-SemiBold"
    static let bodyRegular    = "HankenGrotesk-Regular"
    static let bodyMedium     = "HankenGrotesk-Medium"
    static let bodySemi       = "HankenGrotesk-SemiBold"
    static let bodyBold       = "HankenGrotesk-Bold"

    private static let all = [
        displayHeavy, displayBold, displaySemi,
        bodyRegular, bodyMedium, bodySemi, bodyBold
    ]

    static func register() {
        for name in all {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                   ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            if let url {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

// MARK: - Semantic Fonts
enum CurioFont {
    /// Editorial display (Schibsted Grotesk). Heavy by default.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        let name: String
        switch weight {
        case .semibold:        name = AppFonts.displaySemi
        case .bold:            name = AppFonts.displayBold
        default:               name = AppFonts.displayHeavy
        }
        return Font.custom(name, size: size)
    }

    /// Body / UI text (Hanken Grotesk).
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:               name = AppFonts.bodyMedium
        case .semibold:             name = AppFonts.bodySemi
        case .bold, .heavy:         name = AppFonts.bodyBold
        default:                    name = AppFonts.bodyRegular
        }
        return Font.custom(name, size: size)
    }

    /// Monospaced label (category pills, diagram titles).
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Cover Gradient Fallback
// Subtle diagonal gradient derived from the story hue, shown behind every
// cover image while it loads or if it fails.
extension LinearGradient {
    static func coverFallback(hue: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.38, brightness: 0.26),
                Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1.0),
                      saturation: 0.30, brightness: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Safe Area (via environment)
// Read once from a root GeometryReader (reliable even with .ignoresSafeArea)
// and injected so full-bleed cards can still respect the notch / home indicator.
private struct SafeTopKey: EnvironmentKey { static let defaultValue: CGFloat = 59 }
private struct SafeBottomKey: EnvironmentKey { static let defaultValue: CGFloat = 34 }

extension EnvironmentValues {
    var safeTop: CGFloat {
        get { self[SafeTopKey.self] }
        set { self[SafeTopKey.self] = newValue }
    }
    var safeBottom: CGFloat {
        get { self[SafeBottomKey.self] }
        set { self[SafeBottomKey.self] = newValue }
    }
}

// Reads the live window safe-area insets (works even when the layout uses
// .ignoresSafeArea, where GeometryReader's safeAreaInsets collapse to zero).
enum SafeArea {
    static func insets() -> EdgeInsets {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            let win = ws.windows.first(where: { $0.isKeyWindow }) ?? ws.windows.first
            if let i = win?.safeAreaInsets, i.top > 0 || i.bottom > 0 {
                return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
            }
        }
        return EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    }
}

// MARK: - Haptics
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }
    static func pop() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
