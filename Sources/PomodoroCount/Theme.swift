import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Button tints

/// A two-stop gradient + matching shadow color for a filled button.
struct ButtonTint {
    let top: Color
    let bottom: Color
    let shadow: Color

    // Classic
    static let tomato = ButtonTint(
        top: Color(red: 1.00, green: 0.45, blue: 0.37),
        bottom: Color(red: 0.82, green: 0.16, blue: 0.17),
        shadow: Color(red: 0.80, green: 0.15, blue: 0.15))

    static let grass = ButtonTint(
        top: Color(red: 0.44, green: 0.78, blue: 0.40),
        bottom: Color(red: 0.20, green: 0.52, blue: 0.22),
        shadow: Color(red: 0.20, green: 0.48, blue: 0.20))

    static let graphite = ButtonTint(
        top: Color(red: 0.44, green: 0.47, blue: 0.52),
        bottom: Color(red: 0.25, green: 0.27, blue: 0.31),
        shadow: Color.black)

    // Synthwave
    static let hotPink = ButtonTint(
        top: Color(hex: 0xFF4D8D), bottom: Color(hex: 0x9D2BD6), shadow: Color(hex: 0xFF2A6D))

    static let electricCyan = ButtonTint(
        top: Color(hex: 0x5BEEFF), bottom: Color(hex: 0x0A8FB8), shadow: Color(hex: 0x05D9E8))

    static let violet = ButtonTint(
        top: Color(hex: 0xC77DFF), bottom: Color(hex: 0x6A1FB0), shadow: Color(hex: 0xB026FF))

    static let neonMint = ButtonTint(
        top: Color(hex: 0x5CFFC6), bottom: Color(hex: 0x00A874), shadow: Color(hex: 0x00F5A0))
}

// MARK: - Palette

/// Everything colour-related the UI needs, so the whole app can be reskinned
/// by swapping one value. `neon` turns on glow/bloom treatments.
struct Palette {
    var neon: Bool

    // Chrome
    var paintsBackground: Bool
    var bgTop: Color
    var bgBottom: Color
    var cardFill: Color
    var cardStroke: Color
    var trackFill: Color
    var trackStroke: Color
    var hairline: Color

    // Type
    var text: Color
    var textDim: Color

    // Accents
    var accent: Color        // brand: count, chart bars
    var accent2: Color       // gradient partner for bars
    var cool: Color          // secondary controls, stat numbers
    var idleColor: Color     // timer text when idle
    var focusColor: Color    // timer text while focusing
    var breakColor: Color    // timer text on a break

    // Filled-button tints
    var hero: ButtonTint
    var idleButton: ButtonTint
    var focusButton: ButtonTint
    var breakButton: ButtonTint

    static let classic = Palette(
        neon: false,
        paintsBackground: false,
        bgTop: .clear, bgBottom: .clear,
        cardFill: Color.primary.opacity(0.05),
        cardStroke: .clear,
        trackFill: Color.primary.opacity(0.07),
        trackStroke: .clear,
        hairline: Color.primary.opacity(0.15),
        text: .primary,
        textDim: .secondary,
        accent: Color(red: 0.88, green: 0.22, blue: 0.19),
        accent2: Color(red: 0.72, green: 0.15, blue: 0.13),
        cool: .primary,
        idleColor: .secondary,
        focusColor: Color(red: 0.88, green: 0.22, blue: 0.19),
        breakColor: Color(red: 0.20, green: 0.52, blue: 0.24),
        hero: .tomato,
        idleButton: .graphite,
        focusButton: .tomato,
        breakButton: .grass)

    static let synthwave = Palette(
        neon: true,
        paintsBackground: true,
        bgTop: Color(hex: 0x2B1B4D), bgBottom: Color(hex: 0x140A26),
        cardFill: Color(hex: 0x241640).opacity(0.65),
        cardStroke: Color(hex: 0x6A4A9E).opacity(0.35),
        trackFill: Color(hex: 0x1B0F33),
        trackStroke: Color(hex: 0x6A4A9E).opacity(0.35),
        hairline: Color(hex: 0x6A4A9E).opacity(0.30),
        text: Color(hex: 0xF3EAFF),
        textDim: Color(hex: 0xA48FC9),
        accent: Color(hex: 0xFF2A6D),
        accent2: Color(hex: 0xB026FF),
        cool: Color(hex: 0x05D9E8),
        idleColor: Color(hex: 0x05D9E8),
        focusColor: Color(hex: 0xB026FF),
        breakColor: Color(hex: 0x00F5A0),
        hero: .hotPink,
        idleButton: .electricCyan,
        focusButton: .violet,
        breakButton: .neonMint)

    var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Environment plumbing

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .classic
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Neon bloom — a no-op unless the palette is a neon one.
    @ViewBuilder
    func neonGlow(_ color: Color, enabled: Bool, radius: CGFloat = 8, opacity: Double = 0.7) -> some View {
        if enabled {
            shadow(color: color.opacity(opacity), radius: radius)
        } else {
            self
        }
    }
}
