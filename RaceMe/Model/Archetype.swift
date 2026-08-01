import Foundation

/// The payoff of S11. Derived from real answers, so two users with different
/// answers genuinely get different cards.
///
/// Deliberately Foundation-only and free of any reference to `RunnerProfile` or
/// SwiftUI. `GhostRunner` needs the pace shapes, and keeping this file clean is
/// what lets the whole race simulator be compiled and run outside Xcode — on a
/// Linux or Windows box — so its behaviour can be measured rather than assumed.
/// The `derive(from:)` half lives with `RunnerProfile`.
enum Archetype: String, Codable, CaseIterable, Sendable {
    case closer, frontrunner, metronome, grinder, kicker

    var name: String {
        switch self {
        case .closer: "The Closer"
        case .frontrunner: "The Frontrunner"
        case .metronome: "The Metronome"
        case .grinder: "The Grinder"
        case .kicker: "The Kicker"
        }
    }

    var blurb: String {
        switch self {
        case .closer: "You don't panic when someone goes early. You just reel them in."
        case .frontrunner: "You'd rather lead from the gun and make everyone else hurt."
        case .metronome: "Same split, every kilometre. Boring is a weapon."
        case .grinder: "You win the races nobody wanted to run."
        case .kicker: "Sit, wait, and take it in the last 200."
        }
    }

    /// How this runner distributes effort, before normalisation.
    ///
    /// Multiplies pace across the opening, middle and closing thirds: above 1 is
    /// slower than their own average, below 1 is faster. A frontrunner goes out
    /// under pace and pays for it late; a kicker sits and saves it.
    private var rawPaceShape: (opening: Double, middle: Double, close: Double) {
        switch self {
        case .closer: (1.02, 1.0, 0.96)
        case .frontrunner: (0.96, 1.0, 1.04)
        case .metronome: (1.0, 1.0, 1.0)
        case .grinder: (1.01, 1.01, 0.99)
        case .kicker: (1.03, 1.02, 0.92)
        }
    }

    /// The shape actually used, rescaled so its duration-weighted mean is exactly 1.
    ///
    /// **This normalisation is load-bearing, and handicap racing is broken
    /// without it.**
    ///
    /// The raw numbers above don't average out. A Grinder's shape works out ~0.7%
    /// slower than their own baseline and a Closer's ~0.2% faster, before either
    /// of them takes a step. Under `.fair` scoring — where you're racing your own
    /// handicap, not the other person — that hands the win to whoever drew the
    /// friendlier archetype, every single time. Measured at 0% wins for the
    /// disadvantaged runner over 300 races.
    ///
    /// Dividing by the weighted mean makes an archetype describe *how* you spend
    /// the race rather than how fast you cover it. It also means a new archetype
    /// can't be accidentally overpowered by being written a bit quick.
    ///
    /// The weights are the durations of the three bands `GhostRunner.step`
    /// integrates over — 0…0.33 ramping opening→middle, 0.33…0.72 flat middle,
    /// 0.72…1 ramping middle→close — so a linear ramp contributes half its weight
    /// to each end.
    var paceShape: (opening: Double, middle: Double, close: Double) {
        let raw = rawPaceShape
        let mean = 0.165 * raw.opening + 0.695 * raw.middle + 0.14 * raw.close
        guard mean > 0 else { return raw }
        return (raw.opening / mean, raw.middle / mean, raw.close / mean)
    }
}
