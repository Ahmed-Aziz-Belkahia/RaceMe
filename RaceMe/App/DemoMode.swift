import Foundation

/// Launch-argument demo driving.
///
/// Two jobs: let a human jump straight to any screen instead of tapping through
/// seventeen onboarding panels every time, and let a CI runner walk the whole
/// app taking screenshots without a UI test target.
///
/// Debug builds only. In Release every one of these is a no-op and the parsing
/// never runs.
enum DemoMode {
    /// Screens a demo launch can open directly.
    enum Screen: String, CaseIterable {
        case coldOpen, hook, pace, compute, card, paywall
        case home, race, postRace, board, profile, spectate

        /// Whether this screen needs answers and history behind it.
        ///
        /// The card and the paywall are onboarding screens, but both are built
        /// *out of* the user's answers — an unseeded paywall has no rival's name
        /// on it and is the wrong thing to be looking at. The first four are
        /// genuinely pre-answer and stay blank on purpose.
        var needsSeed: Bool {
            switch self {
            case .coldOpen, .hook, .pace, .compute: false
            default: true
            }
        }

        /// Where in the onboarding flow this screen lives, if it lives there.
        var onboardingStep: OnboardingStep? {
            switch self {
            case .coldOpen: .coldOpen
            case .hook: .hook
            case .pace: .pace
            case .compute: .compute
            case .card: .card
            case .paywall: .paywall
            default: nil
            }
        }
    }

    #if DEBUG
    /// `-demoScreen home`
    static let screen: Screen? = {
        guard let raw = UserDefaults.standard.string(forKey: "demoScreen") else { return nil }
        return Screen(rawValue: raw)
    }()

    /// `-demoSeed YES` — populated profile and race history without the flow.
    static let seedsProfile: Bool =
        UserDefaults.standard.bool(forKey: "demoSeed") || (screen?.needsSeed ?? false)

    /// `-demoFreeze YES` — stops the ambient drift and the simulated field so a
    /// screenshot is reproducible frame to frame.
    static let freezes: Bool = UserDefaults.standard.bool(forKey: "demoFreeze")
    #else
    static let screen: Screen? = nil
    static let seedsProfile = false
    static let freezes = false
    #endif

    static var isActive: Bool { screen != nil || seedsProfile }

    // MARK: Seeding

    /// A believable mid-life user: a named rival, a handle, a record, and enough
    /// history that the trend chart and the photo-finish shelf have something in
    /// them.
    @MainActor
    static func seed(_ profile: RunnerProfile) {
        guard seedsProfile else { return }
        // Seeding the answers and skipping the flow are separate things. A demo
        // launch aimed at the Racer Card wants the answers *and* to still be
        // inside onboarding, or there's no card to look at.
        profile.completedOnboarding = screen?.onboardingStep == nil
        profile.handle = "ahmad"
        profile.mark = .blade
        profile.selfImage = .neverLose
        profile.comfortableMileSeconds = 8 * 60 + 10
        profile.goals = [.faster5K, .beatSomeone]
        profile.rivalName = "Karim"
        profile.frequency = .twice
        profile.window = .dawn
        profile.driver = .someoneAhead
        profile.careerWins = 14
        profile.careerLosses = 9
        profile.totalRaces = 23
        profile.isSubscribed = true
        profile.learnedPaceSecPerKm = 292
        // Permissions stay false — a seeded demo should never look like it
        // silently granted itself notifications or location.
    }

    /// Runs real races headlessly and saves the results.
    ///
    /// Not fixtures. Each of these is the actual `RaceEngine` ticked to the line
    /// against actual `GhostRunner` physics, so the seeded history has genuine
    /// splits and genuine photo finishes — which is the only way to see whether
    /// the slit-scan renderer is any good.
    /// Emits a line only when a demo launch is driving the app. Read back off
    /// the simulator console by `Scripts/screenshots.sh`, which is the only way
    /// to see what a headless CI build is actually doing.
    static func log(_ message: String) {
        guard isActive else { return }
        print("[RACEME-DEMO] \(message)")
    }

    /// Runs the races off the main actor, coarsely, then hands back finished
    /// results.
    ///
    /// The first version did this inline on the main actor at a fixed 60Hz. Six
    /// races, one of them a 10K, is roughly half a million engine steps — and in
    /// an unoptimised Debug build each step sorts the field twice and allocates
    /// a dictionary. It never finished, so the app rendered its background and
    /// nothing else. Adding `Task.yield()` didn't help: the main thread was
    /// still saturated.
    ///
    /// Two changes fix it. The simulation moves to a detached task, because it's
    /// pure computation with no UI in it. And the step size is adaptive — coarse
    /// for the body of the race, fine only through the closing stretch where the
    /// photo finish actually samples. Same picture at the line, a fraction of
    /// the work.
    static func seedHistory(into history: RaceHistoryService, profile: RunnerProfile) async {
        guard seedsProfile else { return }
        log("seedHistory: begin")

        // Snapshot everything off the profile before leaving the main actor.
        let inputs = await MainActor.run {
            (
                user: profile.asRacer(),
                racePace: profile.race5KPaceSecPerKm,
                handicap: profile.handicapPaceSecPerKm,
                shape: profile.archetype.paceShape
            )
        }

        let results = await Task.detached(priority: .userInitiated) { () -> [RaceResult] in
            let distances: [Double] = [5000, 5000, 3000, 5000, 1609.344, 10_000]
            var out: [RaceResult] = []

            for (i, distance) in distances.enumerated() {
                var opponent = MockRoster.racer(
                    index: i, paceSecPerKm: inputs.racePace, seed: UInt64(i) &+ 400
                )
                opponent.displayName = i == 0 ? "Karim" : opponent.displayName

                let config = RaceConfig(
                    distanceMeters: distance,
                    mode: .headToHead,
                    scoring: i % 3 == 0 ? .fair : .raw,
                    participants: RaceCalibrator.buildField(
                        user: inputs.user,
                        userRacePaceSecPerKm: inputs.racePace,
                        opponents: [opponent],
                        difficulty: 0.8,
                        seed: 0xD3E0 &+ UInt64(i)
                    )
                )

                let movement = SimulatedMovementSource(
                    paceSecPerKm: inputs.racePace * (0.98 + Double(i) * 0.008),
                    shape: inputs.shape,
                    seed: 0xD3E0 &+ UInt64(i &* 31)
                )
                let engine = RaceEngine(config: config, movement: movement, seed: 0xD3E0 &+ UInt64(i))
                engine.start()

                var steps = 0
                while !engine.isFinished, steps < 200_000 {
                    // Fine only where the picture is taken.
                    let dt = engine.remainingMeters < 80 ? 1.0 / 60.0 : 1.0 / 8.0
                    engine.tick(dt: dt)
                    steps += 1
                }

                var result = engine.makeResult(baselinePace: inputs.handicap, isPR: i == 2)
                result.finishedAt = Date().addingTimeInterval(-Double(i + 1) * 86_400 * 2.5)
                out.append(result)
            }
            return out
        }.value

        log("seedHistory: simulated \(results.count) races")
        for result in results {
            try? await history.save(result)
        }
        log("seedHistory: saved")
    }
}
