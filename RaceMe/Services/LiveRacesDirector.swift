import Foundation
import Observation
import QuartzCore

/// Keeps eight races permanently in progress.
///
/// The Live now strip is social proof, and empty social proof is worse than
/// none — a strip with nothing in it tells a new user that nobody uses this.
/// So the director always has races running, at staggered start offsets, and
/// replaces each one the moment it finishes.
///
/// These are real engines, not animations: the same `RaceEngine` and the same
/// `GhostRunner` physics the user's own races use. Which means a spectated race
/// genuinely can turn, and the spectator screen is showing the same thing the
/// racer is.
@MainActor
@Observable
final class LiveRacesDirector: SpectatorService {
    private(set) var races: [LiveRace] = []

    /// Reactions that arrived for a race in the last few seconds. The racer's
    /// own screen reads this.
    private(set) var incomingReactions: [UUID: [Reaction]] = [:]

    @ObservationIgnored private var engines: [UUID: RaceEngine] = [:]
    @ObservationIgnored private var spectatorCounts: [UUID: Int] = [:]
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var rng = Rng(seed: 0x11FE)
    @ObservationIgnored private var seedCounter: UInt64 = 0

    private let targetCount = 8
    private let distances: [Double] = [1609.344, 3000, 5000, 5000, 5000, 10_000, 800, 5000]

    // MARK: Lifecycle

    func start() {
        guard ticker == nil else { return }
        if races.isEmpty { seedInitialRaces() }
        ticker = Task { @MainActor [weak self] in
            var last = CACurrentMediaTime()
            // 12Hz is plenty for a background field. The strip's micro-lanes
            // interpolate on top of this; the ProMotion budget belongs to
            // whatever race the user is actually looking at.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(83))
                guard let self else { return }
                let now = CACurrentMediaTime()
                let dt = min(now - last, 0.5)
                last = now
                self.advance(dt: dt)
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: SpectatorService

    func liveRaces() async -> [LiveRace] { races }

    func react(to raceID: UUID, from handle: String) async {
        incomingReactions[raceID, default: []].append(Reaction(from: handle, at: Date()))
        spectatorCounts[raceID, default: 1] += 0
    }

    /// Hand the live engine to a spectator screen so it can drive it at display
    /// rate rather than watching a 12Hz snapshot stutter.
    func engine(for raceID: UUID) -> RaceEngine? { engines[raceID] }

    func drainReactions(for raceID: UUID) -> [Reaction] {
        let out = incomingReactions[raceID] ?? []
        incomingReactions[raceID] = []
        return out
    }

    // MARK: Internals

    private func seedInitialRaces() {
        for i in 0..<targetCount {
            let race = makeRace(index: i)
            // Stagger, so the strip shows races at every stage of their life
            // instead of eight simultaneous starts.
            let headStart = rng.range(20, 60 + Double(i) * 25)
            advanceEngine(engines[race.id], by: headStart)
            races.append(race)
        }
    }

    private func makeRace(index: Int) -> LiveRace {
        seedCounter &+= 1
        let distance = distances[index % distances.count]
        var local = Rng(seed: 0xB0B0 &+ seedCounter)
        let fieldSize = local.chance(0.55) ? 2 : Int(local.range(3, 6))
        let basePace = local.range(230, 400)

        // Distinct roster slots, so no race ever fields two people with the same
        // name — and fresh IDs, so identities never collide across races.
        var slots = Array(0..<MockRoster.names.count)
        var picked: [Int] = []
        for _ in 0..<fieldSize {
            let i = Int(local.range(0, Double(slots.count)))
            picked.append(slots.remove(at: min(i, slots.count - 1)))
        }

        // The "user" slot of a spectated race is just its featured runner.
        var featured = MockRoster.racer(index: picked[0], paceSecPerKm: basePace, seed: seedCounter)
        featured = withFreshID(featured)
        featured.isUser = true

        let opponents = picked.dropFirst().enumerated().map { i, slot in
            withFreshID(MockRoster.racer(
                index: slot,
                paceSecPerKm: basePace * local.range(0.97, 1.05),
                seed: seedCounter &+ UInt64(i)
            ))
        }

        let config = RaceConfig(
            distanceMeters: distance,
            mode: fieldSize == 2 ? .headToHead : .group,
            scoring: local.chance(0.5) ? .fair : .raw,
            participants: RaceCalibrator.buildField(
                user: featured,
                userRacePaceSecPerKm: basePace,
                opponents: opponents,
                difficulty: 0.6,
                seed: 0xC0DE &+ seedCounter
            )
        )

        let movement = SimulatedMovementSource(
            paceSecPerKm: basePace,
            shape: (1.01, 1.0, 0.96),
            seed: 0xFEED &+ seedCounter
        )
        let engine = RaceEngine(config: config, movement: movement, seed: 0xACED &+ seedCounter)
        engine.start()
        engines[config.id] = engine
        spectatorCounts[config.id] = Int(local.range(1, 60))

        return LiveRace(
            id: config.id,
            config: config,
            snapshot: snapshot(from: engine),
            spectators: spectatorCounts[config.id] ?? 1,
            startedAt: Date()
        )
    }

    /// Every live race is watchable by whoever's in it, so the featured runner
    /// gets a name the strip can print without reading like a placeholder.
    func featuredName(_ race: LiveRace) -> String { race.config.user.displayName }

    /// Ticks every engine, and only touches the published roster when something
    /// a view can actually see has changed.
    ///
    /// The earlier version rebuilt `races` on every tick to carry fresh
    /// positions. That made the whole Live-now strip — eight cards, eight
    /// canvases — re-lay-out twelve times a second on the home screen, to move
    /// dots by a couple of points. Positions now come straight off the engines
    /// at draw time; this only republishes when a race is retired and replaced,
    /// or when a spectator count changes.
    private func advance(dt: Double) {
        var rosterChanged = false
        var updated: [LiveRace] = []
        updated.reserveCapacity(races.count)

        for race in races {
            guard let engine = engines[race.id] else {
                rosterChanged = true
                continue
            }
            engine.tick(dt: dt)

            if engine.isFinished {
                // Retire and immediately replace, so the count never dips and
                // the strip is never empty.
                engines[race.id] = nil
                spectatorCounts[race.id] = nil
                incomingReactions[race.id] = nil
                updated.append(makeRace(index: Int(seedCounter) % distances.count))
                rosterChanged = true
                continue
            }

            // Spectator counts drift the way real ones do: up as a race gets
            // close, down once it's decided.
            var next = race
            if rng.chance(dt * 0.5) {
                let margin = leaderMargin(engine)
                let delta = margin < 15 ? Int(rng.range(0, 3)) : Int(rng.range(-1, 2))
                let count = max(1, (spectatorCounts[race.id] ?? 1) + delta)
                if count != race.spectators {
                    spectatorCounts[race.id] = count
                    next.spectators = count
                    rosterChanged = true
                }
            }
            updated.append(next)
        }

        while updated.count < targetCount {
            updated.append(makeRace(index: updated.count))
            rosterChanged = true
        }

        if rosterChanged { races = updated }
    }

    private func withFreshID(_ racer: Racer) -> Racer {
        Racer(
            id: UUID(),
            handle: racer.handle,
            displayName: racer.displayName,
            mark: racer.mark,
            isUser: racer.isUser,
            handicapPaceSecPerKm: racer.handicapPaceSecPerKm,
            pb5K: racer.pb5K,
            careerWins: racer.careerWins,
            careerLosses: racer.careerLosses,
            colorIndex: racer.colorIndex
        )
    }

    private func advanceEngine(_ engine: RaceEngine?, by seconds: Double) {
        guard let engine else { return }
        // Coarse steps are fine for a head start nobody watched happen.
        var remaining = seconds
        while remaining > 0 {
            engine.tick(dt: min(0.1, remaining))
            remaining -= 0.1
        }
    }

    private func leaderMargin(_ engine: RaceEngine) -> Double {
        let sorted = engine.config.participants
            .map { engine.state($0.id).scoredPosition }
            .sorted(by: >)
        guard sorted.count > 1 else { return 0 }
        return sorted[0] - sorted[1]
    }

    private func snapshot(from engine: RaceEngine) -> RaceSnapshot {
        var states: [UUID: RacerState] = [:]
        for racer in engine.config.participants {
            states[racer.id] = engine.state(racer.id)
        }
        let leadDistance = states.values.map(\.distance).max() ?? 0
        return RaceSnapshot(
            elapsed: engine.elapsed,
            states: states,
            phase: engine.isFinished ? .finished : (engine.isClosing ? .closing : .running),
            progress: min(leadDistance / engine.distanceMeters, 1)
        )
    }
}

import QuartzCore
