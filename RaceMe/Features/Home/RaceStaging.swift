import Foundation

/// Picks the race the app puts in front of you.
///
/// Home always has one of these ready, chosen from onboarding answers, so a new
/// user never lands on an empty screen and an existing one never has to decide
/// what to do. The choice is driven by `Driver` (what actually makes them push)
/// and by whether they named a rival — both collected in onboarding, both used
/// here by name.
@MainActor
enum RaceStaging {
    static func stage(
        for profile: RunnerProfile,
        services: AppServices,
        seed: UInt64 = 0x5D06E
    ) async -> StagedRace {
        let user = profile.asRacer()
        let mode = profile.driver.preferredMode
        let distance = preferredDistance(for: profile)

        var opponents: [Racer] = []
        var rationale: String

        switch mode {
        case .ghost:
            // Someone driven by their own numbers gets their own ghost. And if
            // they have no history yet, they get a version of themselves pitched
            // just above their stated pace — which is still a real race.
            let ghost = try? await services.history.ghost(for: distance, user: user)
            opponents = [ghost].compactMap { $0 }
            rationale = "You said your own numbers are what move you. Here they are, on the line beside you."

        case .headToHead:
            let pool = (try? await services.directory.availableOpponents(
                near: profile.race5KPaceSecPerKm, count: 4
            )) ?? []
            var pick = pool.first
            // The named rival wins the slot outright. This is the first of the
            // places their name shows up after onboarding.
            if let rival = profile.rivalMention {
                pick = Racer(
                    handle: rival.lowercased(),
                    displayName: rival,
                    mark: .blade,
                    isUser: false,
                    handicapPaceSecPerKm: profile.race5KPaceSecPerKm * 0.985,
                    colorIndex: 0
                )
                rationale = profile.driver == .someoneGaining
                    ? "\(rival) starts behind you. See how long that lasts."
                    : "\(rival)'s pace, on the line, right now."
            } else {
                rationale = profile.driver == .someoneGaining
                    ? "Someone your speed, starting behind you."
                    : "Someone about four seconds a kilometre quicker. Catchable."
            }
            opponents = [pick].compactMap { $0 }

        case .group:
            opponents = (try? await services.directory.availableOpponents(
                near: profile.race5KPaceSecPerKm, count: 3
            )) ?? []
            rationale = "Three others, all within range. Somebody's finishing last."

        case .league:
            opponents = (try? await services.directory.availableOpponents(
                near: profile.race5KPaceSecPerKm, count: 3
            )) ?? []
            rationale = "League race. Points on the table."
        }

        // No opponents at all is not an empty screen — it's a ghost race.
        if opponents.isEmpty {
            let ghost = try? await services.history.ghost(for: distance, user: user)
            opponents = [ghost].compactMap { $0 }
            rationale = "Nobody's out there at your pace yet. Race yourself and give them something to chase."
        }

        // Handicap racing is the default for anyone who isn't already confident,
        // because without it a beginner loses every race and is gone by week two.
        let scoring: Scoring = profile.selfImage == .neverLose ? .raw : .fair

        let config = RaceConfig(
            distanceMeters: distance,
            mode: mode,
            scoring: scoring,
            participants: RaceCalibrator.buildField(
                user: user,
                userRacePaceSecPerKm: profile.race5KPaceSecPerKm,
                opponents: opponents,
                difficulty: profile.selfImage.difficulty,
                seed: seed
            )
        )

        return StagedRace(
            config: config,
            rationale: rationale,
            projectedOutcome: RaceCalibrator.project(config: config, scoring: scoring)
        )
    }

    /// Distance follows the goal they picked, not a default.
    static func preferredDistance(for profile: RunnerProfile) -> Double {
        if profile.goals.contains(.faster5K) { return 5000 }
        switch profile.selfImage {
        case .justStarting: return 1609.344
        case .whenIFeelLikeIt: return 3000
        case .trainingForSomething, .neverLose: return 5000
        }
    }

    /// The first week, built from their stated frequency and usual run window.
    /// Shown on the compute screen while it's genuinely being computed.
    static func firstWeek(for profile: RunnerProfile) -> [PlannedRace] {
        let count = profile.frequency.perWeek
        let distance = preferredDistance(for: profile)
        let calendar = Calendar.current
        // Space them evenly rather than clumping — someone racing three times a
        // week should not be handed three consecutive days.
        let spacing = max(1, 7 / max(count, 1))
        return (0..<count).map { i in
            let day = calendar.date(
                byAdding: .day, value: i * spacing, to: Date()
            ) ?? Date()
            let at = calendar.date(
                bySettingHour: profile.window.notifyHour + 1, minute: 0, second: 0, of: day
            ) ?? day
            return PlannedRace(
                date: at,
                distanceMeters: i == count - 1 ? distance : distance * 0.6,
                label: i == count - 1 ? "Race" : "Tune-up"
            )
        }
    }
}

struct PlannedRace: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let distanceMeters: Double
    let label: String
}
