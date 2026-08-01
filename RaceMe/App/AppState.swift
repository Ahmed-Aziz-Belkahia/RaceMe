import SwiftUI
import Observation

/// Everything the app knows, in one place.
///
/// There's no database and no backend here — the profile round-trips through
/// `UserDefaults` and everything else lives behind the service protocols. When a
/// real backend arrives, this class is the only thing that changes.
@MainActor
@Observable
final class AppState {
    let profile: RunnerProfile
    let liveRaces = LiveRacesDirector()
    let services: AppServices

    var tab: Tab = .home
    var stagedRace: StagedRace?
    var recentResults: [RaceResult] = []
    var league: League?
    var friendsBoard: [LeaderboardEntry] = []

    /// A race in progress, presented full screen over everything.
    var activeRace: RaceViewModel?
    /// The finish being shown.
    var postRace: RaceResult?
    /// A race someone else is running, being watched.
    var spectating: LiveRace?
    /// Arrived from a tapped challenge link and waiting to be accepted.
    var pendingChallenge: Challenge?

    /// Dev build only. Runs the movement simulator instead of GPS so the whole
    /// product is demoable at a desk — which you need constantly when the hero
    /// screen is a live race.
    var useSimulatedMovement: Bool = {
        #if targetEnvironment(simulator)
        return true
        #elseif DEBUG
        return true
        #else
        return false
        #endif
    }()

    enum Tab: String, CaseIterable, Identifiable {
        case home, board, you
        var id: String { rawValue }
        var label: String {
            switch self {
            case .home: "RACE"
            case .board: "BOARD"
            case .you: "YOU"
            }
        }
        var icon: String {
            switch self {
            case .home: "figure.run"
            case .board: "list.number"
            case .you: "person.fill"
            }
        }
    }

    private static let profileKey = "raceme.profile.v1"

    init() {
        // Restore, or start clean.
        if let data = UserDefaults.standard.data(forKey: Self.profileKey),
           let decoded = try? JSONDecoder().decode(RunnerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = RunnerProfile()
        }
        services = AppServices(spectator: liveRaces)
    }

    func start() {
        Haptics.shared.prepare()
        DemoMode.seed(profile)
        DemoMode.log("start: screen=\(DemoMode.screen?.rawValue ?? "nil") seeds=\(DemoMode.seedsProfile) onboarded=\(profile.completedOnboarding)")
        liveRaces.start()
        Task {
            await DemoMode.seedHistory(into: services.history, profile: profile)
            DemoMode.log("refresh: begin")
            await refresh()
            DemoMode.log("refresh: done staged=\(stagedRace != nil) results=\(recentResults.count) league=\(league != nil)")
            applyDemoScreen()
        }
    }

    /// Opens whatever `-demoScreen` asked for, once there's data behind it.
    private func applyDemoScreen() {
        guard let screen = DemoMode.screen else { return }
        DemoMode.log("applyDemoScreen: \(screen.rawValue)")
        switch screen {
        case .home: tab = .home
        case .board: tab = .board
        case .profile: tab = .you
        case .race: startStagedRace()
        case .postRace: postRace = recentResults.first
        case .spectate: spectating = liveRaces.races.first
        case .coldOpen, .hook, .pace, .compute, .card, .paywall:
            // Handled by RootView, which drops straight into the flow at that
            // step rather than starting it from the top.
            break
        }
        DemoMode.log("applyDemoScreen: done tab=\(tab.rawValue) race=\(activeRace != nil) post=\(postRace != nil) spectate=\(spectating != nil)")
    }

    func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.profileKey)
    }

    func refresh() async {
        let user = profile.asRacer()
        stagedRace = await RaceStaging.stage(for: profile, services: services)
        recentResults = (try? await services.history.recent(limit: 12)) ?? []
        league = try? await services.leaderboards.league(user: user)
        friendsBoard = (try? await services.leaderboards.board(.friends, user: user)) ?? []
    }

    // MARK: Racing

    /// Build and present a race. One entry point, so every route into a race —
    /// the home hero, a rematch, a challenge link, the league — goes through the
    /// same construction and gets the same movement source.
    func startRace(_ config: RaceConfig, seed: UInt64 = 0x5241_4345) {
        guard activeRace == nil else { return }
        let movement: MovementSource = useSimulatedMovement
            ? SimulatedMovementSource(
                paceSecPerKm: profile.race5KPaceSecPerKm,
                shape: profile.archetype.paceShape
              )
            : GPSMovementSource()

        let model = RaceViewModel(
            config: config, movement: movement, profile: profile, services: services, seed: seed
        )
        model.onFinish = { [weak self] result in
            guard let self else { return }
            saveProfile()
            Task { await self.refresh() }
        }
        activeRace = model
    }

    func startStagedRace() {
        guard let staged = stagedRace else { return }
        startRace(staged.config)
    }

    func rematch(_ result: RaceResult) {
        var config = result.config
        config.id = UUID()
        // Fresh seed, so the rematch isn't a replay of the same ghost behaviour.
        startRace(config, seed: UInt64(abs(UUID().hashValue)))
    }

    func endRacePresentation(with result: RaceResult?) {
        activeRace?.teardown()
        activeRace = nil
        // One presentation at a time. Setting both in the same turn of the run
        // loop makes UIKit drop the second cover on the floor.
        guard let result else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            postRace = result
        }
    }

    // MARK: Challenge links

    func handle(url: URL) {
        guard let challenge = ChallengeLink.decode(url) else { return }
        pendingChallenge = challenge
        Haptics.shared.play(.commit)
    }

    func acceptPendingChallenge() {
        guard let challenge = pendingChallenge else { return }
        pendingChallenge = nil
        startRace(
            ChallengeLink.race(from: challenge, user: profile.asRacer()),
            seed: challenge.seed
        )
    }

    // MARK: Ghost racing

    /// Your own past run, as an opponent. Available on day one with zero
    /// friends, which is the whole point of it.
    func startGhostRace(distanceMeters: Double? = nil) {
        let distance = distanceMeters ?? RaceStaging.preferredDistance(for: profile)
        Task { @MainActor in
            let user = profile.asRacer()
            guard let ghost = try? await services.history.ghost(for: distance, user: user) else { return }
            startRace(RaceConfig(
                distanceMeters: distance,
                mode: .ghost,
                scoring: .raw,
                participants: [user, ghost].compactMap { $0 }
            ))
        }
    }
}
