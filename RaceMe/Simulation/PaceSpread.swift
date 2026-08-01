import Foundation

/// How an opponent's pace is drawn relative to the user's.
///
/// Split out of `RaceCalibrator` and kept Foundation-only for one reason: the
/// validation harness can compile it. The first version of that harness raced
/// hand-picked paces (290 against 292) and so never exercised the *distribution*
/// — which was drawing three-sigma opponents ten percent faster than the user
/// and turning a 5K into a two-minute beating. Anything that decides whether a
/// race is close belongs where it can be measured.
enum PaceSpread {
    /// How the field should be pitched against this user.
    enum Intent: Sendable {
        /// Genuinely in doubt. Default for real racing.
        case tossUp
        /// The user is meant to win, narrowly and believably. Used by the taste
        /// race in onboarding — losing your first race is a strange thing to
        /// charge money after.
        case userFavoured(byPercent: Double)
        /// The user is meant to be stretched.
        case stretch
    }

    /// Centre of the distribution, as a multiplier on the user's race pace.
    /// Above 1 is slower than the user.
    static func centre(intent: Intent, difficulty: Double) -> Double {
        switch intent {
        case .tossUp:
            // Harder self-image → opponents pitched right on the user's number.
            // Softer → opponents pitched fractionally behind, so a beginner has
            // something they can actually catch.
            return lerp(1.045, 0.998, difficulty)
        case .userFavoured(let pct):
            return 1 + pct
        case .stretch:
            return lerp(1.0, 0.96, difficulty)
        }
    }

    /// One standard deviation, as a fraction of pace. Small on purpose: over a
    /// 5K, one percent is fifteen seconds.
    static let sigma = 0.012
    static let floor = 0.96
    static let ceiling = 1.07

    /// Seconds per km for one opponent.
    static func opponentPace(
        userRacePaceSecPerKm: Double,
        difficulty: Double,
        intent: Intent,
        rng: inout Rng
    ) -> Double {
        let sample = centre(intent: intent, difficulty: difficulty) + rng.gaussian() * sigma
        return userRacePaceSecPerKm * min(max(sample, floor), ceiling)
    }
}
