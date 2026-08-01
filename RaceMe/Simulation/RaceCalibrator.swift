import Foundation

/// Builds fields that produce close races.
///
/// A race that finishes ninety seconds apart is not a race, it's two runs. The
/// whole product depends on the gap being live for most of the distance and the
/// result being in doubt at the line.
enum RaceCalibrator {
    /// How the field should be pitched against this user.
    enum Intent {
        /// Genuinely in doubt. Default for real racing.
        case tossUp
        /// The user is meant to win, narrowly and believably. Used by the taste
        /// race in onboarding — they've never run this app before, and losing
        /// their first race is a strange thing to charge money after.
        case userFavoured(byPercent: Double)
        /// The user is meant to be stretched.
        case stretch
    }

    /// Seconds per km for one opponent.
    static func opponentPace(
        userRacePaceSecPerKm: Double,
        difficulty: Double,
        intent: Intent,
        rng: inout Rng
    ) -> Double {
        // Centre of the distribution, as a multiplier on the user's race pace.
        // >1 means slower than the user.
        let centre: Double = {
            switch intent {
            case .tossUp:
                // Harder self-image → opponents pitched right on the user's number.
                // Softer → opponents pitched fractionally behind, so a beginner
                // has something they can actually catch.
                return lerp(1.045, 0.998, difficulty)
            case .userFavoured(let pct):
                return 1 + pct
            case .stretch:
                return lerp(1.0, 0.96, difficulty)
            }
        }()

        // Spread. Some races should be blowouts in both directions — a field
        // where every opponent is within 1% forever is its own kind of fake.
        let spread = 0.028
        let sample = centre + rng.gaussian() * spread
        return userRacePaceSecPerKm * min(max(sample, 0.9), 1.2)
    }

    /// A full field, calibrated. Opponent colours are assigned here so the
    /// warm/cool rule can't be violated downstream.
    static func buildField(
        user: Racer,
        userRacePaceSecPerKm: Double,
        opponents: [Racer],
        difficulty: Double,
        intent: Intent = .tossUp,
        seed: UInt64
    ) -> [Racer] {
        var rng = Rng(seed: seed)
        var field: [Racer] = [user]
        for (i, var opponent) in opponents.enumerated() {
            opponent.handicapPaceSecPerKm = opponentPace(
                userRacePaceSecPerKm: userRacePaceSecPerKm,
                difficulty: difficulty,
                intent: intent,
                rng: &rng
            )
            opponent.colorIndex = i
            opponent.isUser = false
            field.append(opponent)
        }
        return field
    }

    /// Honest projection for the Home hero card. Uses handicap pace under fair
    /// scoring — under which a slower runner really can be favoured.
    static func project(config: RaceConfig, scoring: Scoring) -> StagedRace.Projection {
        guard let opponent = config.opponents.first else { return .tooClose }
        let d = config.distanceMeters / 1000
        switch scoring {
        case .raw:
            let delta = (opponent.handicapPaceSecPerKm - config.user.handicapPaceSecPerKm) * d
            if abs(delta) < 12 { return .tooClose }
            return delta > 0 ? .youFavoured(bySeconds: delta) : .theyFavoured(bySeconds: -delta)
        case .fair:
            // Under handicap, form relative to your own baseline is what decides
            // it — so it's close by construction, and we say so.
            return .tooClose
        }
    }
}
