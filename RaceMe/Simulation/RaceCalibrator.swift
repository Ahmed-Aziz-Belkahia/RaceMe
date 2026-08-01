import Foundation

/// Builds fields that produce close races.
///
/// A race that finishes ninety seconds apart is not a race, it's two runs. The
/// whole product depends on the gap being live for most of the distance and the
/// result being in doubt at the line.
enum RaceCalibrator {
    /// The distribution itself lives in `PaceSpread`, which is Foundation-only
    /// so the validation harness can measure it.
    typealias Intent = PaceSpread.Intent

    /// Seconds per km for one opponent.
    static func opponentPace(
        userRacePaceSecPerKm: Double,
        difficulty: Double,
        intent: Intent,
        rng: inout Rng
    ) -> Double {
        PaceSpread.opponentPace(
            userRacePaceSecPerKm: userRacePaceSecPerKm,
            difficulty: difficulty,
            intent: intent,
            rng: &rng
        )
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

    /// Honest projection for the Home hero card.
    ///
    /// Takes the user's *race* pace explicitly. Comparing an opponent's race
    /// pace against the user's handicap — which is their easy, everyday pace —
    /// is comparing two different efforts, and it put "They're 210s faster on
    /// form" on the most important card in the app.
    static func project(
        config: RaceConfig,
        scoring: Scoring,
        userRacePaceSecPerKm: Double
    ) -> StagedRace.Projection {
        guard let opponent = config.opponents.first else { return .tooClose }
        let d = config.distanceMeters / 1000
        switch scoring {
        case .raw:
            let delta = (opponent.handicapPaceSecPerKm - userRacePaceSecPerKm) * d
            if abs(delta) < 12 { return .tooClose }
            return delta > 0 ? .youFavoured(bySeconds: delta) : .theyFavoured(bySeconds: -delta)
        case .fair:
            // Under handicap, form relative to your own baseline is what decides
            // it — so it's close by construction, and we say so.
            return .tooClose
        }
    }
}
