import SwiftUI

/// Two registers, and a hard wall between them.
///
/// **Bib** — condensed, black weight, monospaced digits, tight tracking. This is
/// the voice of the app: gaps, splits, distances, positions, times. Fat numerals
/// safety-pinned to a vest.
///
/// **Prose** — quiet, gets out of the way, never competes with a number. Named
/// `Prose` rather than `Body` because inside any `View`, `Body` resolves to the
/// view's own `Body` associated type and shadows the scale entirely.
///
/// Nothing under 17pt appears on a screen used while running. Nothing is thin.
enum Bib {
    /// The gap. The single biggest thing on the live race screen.
    static func hero(_ size: CGFloat = 118) -> Font {
        .system(size: size, weight: .black, design: .default)
            .width(.condensed)
            .monospacedDigit()
    }

    /// Big secondary numerals — pace, elapsed, splits on the post-race screen.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default)
            .width(.condensed)
            .monospacedDigit()
    }

    /// Chalk numerals on the lane, countdown digits, bib numbers.
    static func chalk(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
            .width(.compressed)
            .monospacedDigit()
    }

    /// Splits, deltas, anything tabular. Real mono so digits never reflow.
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// All-caps micro label. The only place tracking goes positive.
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .default)
            .width(.condensed)
    }
}

enum Prose {
    /// Screen titles. One question per screen wears this.
    static func title(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold)
    }
    static func headline(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold)
    }
    /// Never below 17.
    static func copy(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular)
    }
    static func caption(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium)
    }
}

// MARK: - Tracking

/// Tracking is size-specific. Large numerals read too loose as they grow and
/// need to be pulled in; small caps labels need pushing apart. One global
/// letter-spacing value would be wrong at one end or the other.
extension View {
    /// For Bib.hero / Bib.numeral at display sizes.
    func bibTracking(_ size: CGFloat) -> some View {
        tracking(size >= 72 ? -3.5 : size >= 40 ? -1.6 : -0.7)
    }

    /// For all-caps micro labels.
    func labelTracking() -> some View {
        tracking(1.4)
    }
}

// MARK: - Ready-made label

/// The recurring all-caps chalk label: `DISTANCE`, `LEAD`, `WEEK 6`.
struct TrackLabel: View {
    let text: String
    var color: Color = Track.chalkFaint
    var size: CGFloat = 12

    init(_ text: String, color: Color = Track.chalkFaint, size: CGFloat = 12) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(Bib.label(size))
            .labelTracking()
            .foregroundStyle(color)
    }
}

// MARK: - Formatting

enum Fmt {
    /// `7:42` / `1:04:09`. Always monospaced digits at the call site.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// `7:42.31` — split precision.
    static func clockPrecise(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--.--" }
        let m = Int(seconds) / 60
        let s = seconds - Double(m * 60)
        return String(format: "%d:%05.2f", m, s)
    }

    /// `4:38` per km, or per mile depending on the unit setting.
    static func pace(_ secondsPerKm: Double, unit: DistanceUnit = .km) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0, secondsPerKm < 3600 else { return "--:--" }
        let v = unit == .km ? secondsPerKm : secondsPerKm * 1.609344
        return String(format: "%d:%02d", Int(v) / 60, Int(v.rounded()) % 60)
    }

    /// `+12` / `−8` / `0`. Uses U+2212 minus, not a hyphen — a hyphen at 118pt
    /// black condensed is a stub and reads as a dash, not a sign.
    static func signedMeters(_ meters: Double) -> String {
        let v = Int(meters.rounded())
        if v == 0 { return "0" }
        return v > 0 ? "+\(v)" : "\u{2212}\(abs(v))"
    }

    /// `+0:04` / `−0:11` for time deltas.
    static func signedClock(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "\u{2212}" : "+"
        let a = abs(seconds)
        return sign + String(format: "%d:%02d", Int(a) / 60, Int(a.rounded()) % 60)
    }

    /// `5.00 km` / `3.11 mi`
    static func distance(_ meters: Double, unit: DistanceUnit = .km, decimals: Int = 2) -> String {
        let v = unit == .km ? meters / 1000 : meters / 1609.344
        return String(format: "%.\(decimals)f", v)
    }

    /// `5K`, `10K`, `1 MI`, `800M` — the way a race is named, not measured.
    static func raceName(_ meters: Double) -> String {
        switch meters {
        case 799...801: return "800M"
        case 1500...1501: return "1500M"
        case 1609...1610: return "1 MI"
        case 4999...5001: return "5K"
        case 9999...10001: return "10K"
        case 21094...21098: return "HALF"
        case 42194...42196: return "MARATHON"
        default:
            return meters < 1000
                ? "\(Int(meters))M"
                : String(format: "%.1fK", meters / 1000).replacingOccurrences(of: ".0K", with: "K")
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case km, mi
    var short: String { self == .km ? "KM" : "MI" }
    var meters: Double { self == .km ? 1000 : 1609.344 }
}
