import SwiftUI

/// What the app's mood is currently doing. The background answers to this.
enum Atmosphere: Equatable, Sendable {
    case idle
    /// You're ahead. The room warms.
    case leading
    /// You're behind. The room cools.
    case trailing
    /// Final 200m. Bloom intensifies.
    case closing
    case won
    case lost

    var bloom: Color {
        switch self {
        case .idle: Track.you
        case .leading, .closing, .won: Track.you
        case .trailing, .lost: Track.them
        }
    }

    /// Peak opacity of the warm bloom. The whole range across every state is
    /// under five percentage points. This is meant to be felt, not seen — if a
    /// user can point at it and describe it, it's too strong.
    var bloomOpacity: Double {
        switch self {
        case .idle: 0.030
        case .leading: 0.058
        case .trailing: 0.036
        case .closing: 0.072
        case .won: 0.068
        case .lost: 0.030
        }
    }

    /// Where the bloom sits. Leading pushes it forward and up; trailing lets it
    /// sink behind you.
    var bloomAnchor: UnitPoint {
        switch self {
        case .idle: .init(x: 0.5, y: 0.34)
        case .leading, .closing, .won: .init(x: 0.52, y: 0.24)
        case .trailing, .lost: .init(x: 0.48, y: 0.62)
        }
    }
}

private struct AtmosphereKey: EnvironmentKey {
    static let defaultValue: Atmosphere = .idle
}

extension EnvironmentValues {
    var atmosphere: Atmosphere {
        get { self[AtmosphereKey.self] }
        set { self[AtmosphereKey.self] = newValue }
    }
}

/// The slow ambient field the whole app sits on.
///
/// Glass with nothing behind it refracts nothing and looks like grey plastic.
/// This gives every glass surface something to bend. Two very large radial
/// blooms drift on long, mutually-prime periods so the pattern never visibly
/// repeats, plus a faint chalk-dust grain so large flat areas don't band on OLED.
///
/// Reduce Motion freezes it completely — no drift, no phase, just the static
/// field at the current atmosphere.
struct AmbientBackground: View {
    @Environment(\.atmosphere) private var atmosphere
    @Environment(\.motion) private var motion

    var body: some View {
        ZStack {
            Track.base.ignoresSafeArea()

            if motion.reduced {
                field(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    // 1/30s is plenty — this drifts across minutes. Spending
                    // ProMotion frames on a background that moves 3px a second
                    // would be taking them from the lane, which actually needs them.
                    field(phase: timeline.date.timeIntervalSinceReferenceDate)
                }
            }

            grain
        }
        .ignoresSafeArea()
        .animation(motion.animation(Spring.ambient), value: atmosphere)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func field(phase: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Periods chosen not to share factors, so the two blooms never
            // re-align into an obvious pulse.
            let d1 = CGSize(width: sin(phase / 23.0) * w * 0.10,
                            height: cos(phase / 31.0) * h * 0.06)
            let d2 = CGSize(width: cos(phase / 37.0) * w * 0.12,
                            height: sin(phase / 29.0) * h * 0.08)

            ZStack {
                // Primary bloom — carries the state colour.
                RadialGradient(
                    colors: [atmosphere.bloom.opacity(atmosphere.bloomOpacity), .clear],
                    center: atmosphere.bloomAnchor,
                    startRadius: 0,
                    endRadius: max(w, h) * 0.92
                )
                .offset(d1)

                // Counter-bloom — always the opposite temperature, always fainter.
                // Keeps the field from reading as a flat wash of one colour.
                RadialGradient(
                    colors: [
                        (atmosphere.bloom == Track.you ? Track.them : Track.you)
                            .opacity(atmosphere.bloomOpacity * 0.42),
                        .clear,
                    ],
                    center: .init(x: 0.14, y: 0.86),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.8
                )
                .offset(d2)

                // Vignette. Pulls the eye to the middle third where the gap lives.
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.34)],
                    center: .center,
                    startRadius: h * 0.22,
                    endRadius: h * 0.78
                )
            }
        }
    }

    /// Chalk dust. Kills OLED banding across the large dark flats, and gives the
    /// base a surface instead of a void.
    private var grain: some View {
        Canvas { ctx, size in
            ctx.opacity = 0.035
            ctx.blendMode = .plusLighter
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }
            for _ in 0..<520 {
                let r = rnd() * 1.1 + 0.25
                let rect = CGRect(x: rnd() * size.width, y: rnd() * size.height, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect), with: .color(Track.chalk))
            }
        }
        .ignoresSafeArea()
        // The blend mode is already set inside the Canvas. Setting it again out
        // here applied it twice and pushed the grain from "felt" to "seen".
        .allowsHitTesting(false)
    }
}

extension View {
    /// Sets the app's atmosphere from any screen.
    func atmosphere(_ value: Atmosphere) -> some View {
        environment(\.atmosphere, value)
    }
}
