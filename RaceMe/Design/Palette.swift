import SwiftUI

/// The whole palette. Six colours, no more.
///
/// The warm/cool split is the most load-bearing rule in the app: `you` is always
/// warm rust, `them` is always cool aqua, and nothing else is allowed to be
/// either of those hues. A runner glancing at this screen mid-stride at 5:30am
/// has to resolve who's who pre-attentively — before reading a single glyph.
enum Track {
    /// Deep pre-dawn blue-black. Deliberately not #000000 — glass needs
    /// something with chroma behind it or it refracts nothing and reads as grey.
    static let base = Color(hex: 0x0A0E1A)
    /// Sheets, glass tint, raised surfaces.
    static let elevated = Color(hex: 0x151B2E)
    /// Text and lane chalk. Warm off-white, never pure white.
    static let chalk = Color(hex: 0xF5F3EE)
    /// The user. Track rust. Their dot, their trace, their bar, primary actions.
    static let you = Color(hex: 0xFF5B2E)
    /// Opponents. Cool aqua. Never the user, not once.
    static let them = Color(hex: 0x4DE1C1)
    /// Bib yellow. Records, PRs, lead changes. If it's on screen twice, one is wrong.
    static let signal = Color(hex: 0xFFD84D)

    // MARK: Derived tints
    // Only ever derived from the six above — no new hues enter the app here.

    /// Chalk at reading weight for secondary copy.
    static let chalkDim = chalk.opacity(0.62)
    /// Chalk at label weight — lane numbers, units, captions.
    static let chalkFaint = chalk.opacity(0.34)
    /// The line itself. Painted chalk on rubber is never bright.
    static let laneLine = chalk.opacity(0.16)
    /// Hairline separators between structural regions.
    static let hairline = chalk.opacity(0.09)

    /// Opponent colour ramp. Multiple opponents stay in the cool half of the
    /// wheel and separate by luminance rather than by hue, so `you` remains the
    /// only warm thing on screen no matter how many racers are in the field.
    static func opponent(_ index: Int) -> Color {
        let ramp: [Color] = [
            them,
            Color(hex: 0x3FC3D6),
            Color(hex: 0x6FE8A8),
            Color(hex: 0x35A8C9),
            Color(hex: 0x8FF0D6),
            Color(hex: 0x2F8FB8),
        ]
        return ramp[abs(index) % ramp.count]
    }

    /// Colour for a racer by role. The single entry point — no view should ever
    /// pick between `you` and `them` with its own conditional.
    static func racer(isUser: Bool, opponentIndex: Int = 0) -> Color {
        isUser ? you : opponent(opponentIndex)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension ShapeStyle where Self == Color {
    static var chalk: Color { Track.chalk }
    static var you: Color { Track.you }
    static var them: Color { Track.them }
    static var signal: Color { Track.signal }
}
