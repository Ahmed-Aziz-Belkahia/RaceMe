import SwiftUI
import Observation

/// Everything discrete about a live race: what phase it's in, what the ticker is
/// saying, who's in what order, and which haptic fires when.
///
/// The continuous stuff — positions, gaps, pace — lives in `RaceEngine` and is
/// read directly by the lane at display rate. This class only publishes things
/// that change a handful of times per race, so SwiftUI isn't asked to diff a
/// view tree 120 times a second.
@MainActor
@Observable
final class RaceViewModel {
    let engine: RaceEngine
    let config: RaceConfig
    private let profile: RunnerProfile
    private let services: AppServices

    private(set) var phase: RacePhase = .staged
    private(set) var events: [RaceEvent] = []
    /// Ordered by current place. The opponent strip animates against this.
    private(set) var standings: [UUID] = []
    private(set) var result: RaceResult?
    private(set) var isPaused = false
    /// 🔥 that arrived from spectators, still on screen.
    private(set) var liveReactions: [Reaction] = []
    private(set) var fault: MovementFault?

    /// Set when the user has ended the race early and we're asking whether they
    /// meant it. Ending a race mid-run is not recoverable, so it gets a
    /// confirmation — and nothing else in the app does.
    var confirmingEnd = false

    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var reactionTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatRunning = false
    /// Standings are checked off the display link, but places change a handful of
    /// times per race. Rebuilding and comparing the order array 120 times a second
    /// allocates for nothing, so it's throttled to a rate a human can perceive.
    @ObservationIgnored private var standingsClock: Double = 0
    /// Compresses time for the onboarding taste race — 25 seconds of screen time
    /// that has to feel like a real race.
    @ObservationIgnored var timeScale: Double = 1

    var onFinish: ((RaceResult) -> Void)?

    init(config: RaceConfig, movement: MovementSource, profile: RunnerProfile, services: AppServices, seed: UInt64 = 0x5241_4345) {
        self.config = config
        self.profile = profile
        self.services = services
        self.engine = RaceEngine(config: config, movement: movement, splitUnit: profile.unit, seed: seed)
        self.standings = config.participants.map(\.id)
        wireEngine()
    }

    // MARK: Atmosphere
    //
    // The background warms when you're leading and cools when you're behind, by
    // a few percent of opacity. They feel it before they notice it.

    var atmosphere: Atmosphere {
        switch phase {
        case .finished:
            return (result?.userWon ?? false) ? .won : .lost
        case .closing:
            return .closing
        case .staged, .countdown:
            return .idle
        case .running:
            return engine.userState.place == 1 ? .leading : .trailing
        }
    }

    var isClosing: Bool { if case .closing = phase { true } else { false } }
    var isRunning: Bool {
        switch phase { case .running, .closing: true; default: false }
    }

    var headerTitle: String { config.title }
    var opponentsByPlace: [Racer] {
        standings.compactMap { id in config.participants.first { $0.id == id && !$0.isUser } }
    }

    // MARK: Lifecycle

    /// The countdown is a ritual, not a delay. Ten seconds of anticipation buys
    /// more than most features do.
    func beginCountdown() {
        guard case .staged = phase else { return }
        Haptics.shared.warmUp()
        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for n in [3, 2, 1] {
                // Wrapped, so the numeral actually transitions between ticks and
                // the overlay leaves under a spring rather than being cut.
                withAnimation(Spring.snap) { phase = .countdown(n) }
                Haptics.shared.play(.countdownTick(3 - n))
                try? await Task.sleep(for: .milliseconds(820))
                if Task.isCancelled { return }
            }
            Haptics.shared.play(.go)
            withAnimation(Spring.momentum) { phase = .running }
            engine.start()
            startLink()
            startReactionFeed()
        }
    }

    /// Skip the ritual — used when a race is resumed or when the user has already
    /// been counted down once in this session.
    func startImmediately() {
        phase = .running
        engine.start()
        startLink()
        startReactionFeed()
    }

    func pause() {
        guard isRunning else { return }
        isPaused = true
        link?.stop()
        Haptics.shared.stopHeartbeat()
        heartbeatRunning = false
        Haptics.shared.play(.commit)
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        startLink()
        if isClosing { startHeartbeat() }
        Haptics.shared.play(.commit)
    }

    func requestEnd() {
        confirmingEnd = true
        Haptics.shared.play(.select)
    }

    func endEarly() {
        confirmingEnd = false
        teardown()
        phase = .finished
        Haptics.shared.play(.loss)
        finishUp(abandoned: true)
    }

    func teardown() {
        link?.stop()
        link = nil
        countdownTask?.cancel()
        reactionTask?.cancel()
        Haptics.shared.stopHeartbeat()
        heartbeatRunning = false
        engine.movement.stop()
    }

    // MARK: Spectator reactions

    /// A 🔥 landing mid-race is one of the strongest retention mechanics a racing
    /// app has — it makes running feel watched. Light haptic, brief visual, never
    /// enough to break stride.
    func receive(_ reaction: Reaction) {
        liveReactions.append(reaction)
        Haptics.shared.play(.reaction)
        events.append(RaceEvent(
            at: engine.elapsed, kind: .reaction(from: reaction.from),
            text: "\(reaction.from) is watching.", accent: .signal
        ))
        trimEvents()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            self?.liveReactions.removeAll { $0.id == reaction.id }
        }
    }

    // MARK: Internals

    private func wireEngine() {
        engine.onEvent = { [weak self] event in
            guard let self else { return }
            events.append(event)
            trimEvents()
            recomputeStandings()
        }
        engine.onLeadChange = { [weak self] _, userGained in
            // The signature haptic. Sharp transient into a rising rumble when
            // it's yours; the dull falling inverse when it isn't.
            Haptics.shared.play(userGained ? .leadTaken : .leadLost)
            self?.recomputeStandings()
        }
        engine.onSplit = { _, _ in
            Haptics.shared.play(.split)
        }
        engine.onEnterClosing = { [weak self] in
            guard let self else { return }
            withAnimation(Spring.ui) { phase = .closing }
            startHeartbeat()
        }
        engine.onFinish = { [weak self] in
            self?.completeRace()
        }
    }

    private func startLink() {
        link?.stop()
        let link = DisplayLink { [weak self] dt in
            guard let self, !isPaused else { return }
            engine.tick(dt: dt * timeScale)
            fault = engine.movement.fault
            standingsClock += dt
            if standingsClock >= 0.1 {
                standingsClock = 0
                recomputeStandings()
            }
        }
        link.start()
        self.link = link
    }

    /// Spectators arriving while you run.
    ///
    /// Mocked, like everything else without a backend — but the *mechanic* is
    /// real and it's the one being demonstrated: a reaction lands, you feel a
    /// light flick, a name appears for two seconds, and running stops feeling
    /// private. Weighted toward the closing stages, because that's when people
    /// actually watch.
    private func startReactionFeed() {
        reactionTask?.cancel()
        reactionTask = Task { @MainActor [weak self] in
            var rng = Rng(seed: 0x5EE4)
            while !Task.isCancelled {
                let wait = rng.range(14, 38)
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled, isRunning, !isPaused else { return }
                // More eyes late in a close race.
                let close = abs(engine.displayGap) < 25
                let odds = (isClosing ? 0.8 : 0.35) * (close ? 1.0 : 0.55)
                guard rng.chance(odds) else { continue }
                let name = MockRoster.names[Int(rng.range(0, Double(MockRoster.names.count)))].1
                receive(Reaction(from: name, at: Date()))
            }
        }
    }

    private func startHeartbeat() {
        guard !heartbeatRunning else { return }
        heartbeatRunning = true
        Haptics.shared.startHeartbeat { [weak self] in
            self?.engine.closingProgress ?? 0
        }
    }

    private func recomputeStandings() {
        let next = config.participants
            .map { ($0.id, engine.state($0.id).place) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        guard next != standings else { return }
        withAnimation(Spring.reorder) { standings = next }
    }

    private func trimEvents() {
        if events.count > 14 { events.removeFirst(events.count - 14) }
    }

    private func completeRace() {
        teardown()
        withAnimation(Spring.ui) { phase = .finished }
        finishUp(abandoned: false)
    }

    private func finishUp(abandoned: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let baseline = (try? await services.history.baselinePace(
                for: config.distanceMeters, user: config.user
            )) ?? profile.handicapPaceSecPerKm

            let userTime = engine.state(config.user.id).finishTime ?? engine.elapsed
            let previousBest = (try? await services.history.recent(limit: 50))?
                .filter { abs($0.config.distanceMeters - config.distanceMeters) < 1 }
                .map(\.userTime).min()
            let isPR = !abandoned && (previousBest.map { userTime < $0 } ?? true)

            var result = engine.makeResult(baselinePace: baseline, isPR: isPR)
            if abandoned {
                // An abandoned race is not a loss on your record, and it is not a
                // PR. It just didn't happen.
                result.isPersonalRecord = false
            }
            self.result = result

            if !abandoned {
                profile.recordResult(result)
                try? await services.history.save(result)
                try? await services.leaderboards.submit(result: result, points: Points.award(for: result))

                // Outcome haptics. A win is heavy and arrives; a loss is one soft
                // thud. Dignified, not punishing.
                if result.isPersonalRecord {
                    Haptics.shared.play(.record)
                } else if result.userWon {
                    Haptics.shared.play(.win)
                } else {
                    Haptics.shared.play(.loss)
                }
            }
            onFinish?(result)
        }
    }
}
