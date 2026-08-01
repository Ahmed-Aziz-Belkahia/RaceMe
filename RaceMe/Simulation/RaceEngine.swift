import Foundation
import QuartzCore

/// The race itself.
///
/// Deliberately *not* `@Observable`. The lane redraws every display frame at up
/// to 120Hz; routing that through SwiftUI's dependency graph would spend the
/// frame budget on diffing instead of drawing. Views read this class directly
/// from inside a `TimelineView(.animation)`, and the small amount of genuinely
/// discrete state (phase, events, finishing order) is published separately by
/// `RaceViewModel`.
final class RaceEngine {
    let config: RaceConfig
    let scoring: Scoring
    let distanceMeters: Double

    private(set) var elapsed: Double = 0
    private(set) var states: [UUID: RacerState] = [:]
    private(set) var finishedOrder: [UUID] = []
    private(set) var splits: [UUID: [Split]] = [:]

    /// Ring buffer of the last seconds at the line. This is what the slit-scan
    /// photo finish is drawn from — real sampled positions, not a template.
    private(set) var finishSamples: [FinishSample] = []
    private let finishSampleWindow: Double = 9
    private let finishSampleHz: Double = 60
    private var lastFinishSampleAt: Double = -1

    let movement: MovementSource
    private var ghosts: [UUID: GhostRunner] = [:]
    private let userID: UUID

    /// Callbacks the view model hooks into. Cheaper and more precise than
    /// polling for state transitions each frame.
    var onEvent: ((RaceEvent) -> Void)?
    var onLeadChange: ((UUID, _ userGained: Bool) -> Void)?
    var onSplit: ((Int, Double) -> Void)?
    var onEnterClosing: (() -> Void)?
    var onFinish: (() -> Void)?

    // Lead tracking with hysteresis. Without it, two runners within a stride of
    // each other generate a lead-change haptic several times a second, which is
    // both useless and physically unpleasant.
    private var currentLeader: UUID?
    private var candidateLeader: UUID?
    private var candidateSince: Double = 0
    private let leadMarginMeters: Double = 1.6
    private let leadHoldSeconds: Double = 0.9

    private var nextSplitIndex = 1
    private let splitUnitMeters: Double
    private var enteredClosing = false
    private var announcedMarkers: Set<Int> = []
    /// Elapsed time of the first crossing. Anchors the photo-finish window.
    private var firstFinishAt: Double?

    // Surge / fade detection over a short window of each opponent's pace.
    private var paceHistory: [UUID: [(t: Double, pace: Double)]] = [:]
    private var lastSurgeCall: [UUID: Double] = [:]

    private(set) var isFinished = false

    // MARK: Display values
    //
    // Live numbers must never snap or flicker. A gap slides from 8 to 12; it
    // doesn't jump, and it doesn't oscillate ±1 while two runners are level.
    // Smoothing belongs here, at the data, rather than in each view that happens
    // to show the number — and it's critically damped, because a gap readout
    // that overshoots to +14 on its way to +12 is lying to someone at 5:30am.

    /// The headline gap, smoothed, in metres. Signed: positive = user ahead.
    private(set) var displayGap: Double = 0
    /// Current pace, heavily smoothed. Pace is a glanceable number, not a live
    /// instrument — GPS noise at running speed makes the raw value unreadable.
    private(set) var displayPace: Double = 0
    private var gapVelocity: Double = 0
    private var paceVelocity: Double = 0

    private func stepDisplayValues(dt: Double) {
        let gapTarget = headlineGap?.meters ?? 0
        Self.criticallyDamped(&displayGap, &gapVelocity, target: gapTarget, response: 0.38, dt: dt)

        let raw = userState.pace
        // Ignore nonsense (stopped, or a bad fix) rather than dragging the
        // display to zero and back.
        let paceTarget = (raw > 120 && raw < 1200) ? raw : displayPace
        Self.criticallyDamped(&displayPace, &paceVelocity, target: paceTarget, response: 1.1, dt: dt)
    }

    /// Analytic critically-damped step. Stable at any `dt`, which matters when
    /// ProMotion swings the frame interval between 8.3ms and 16.6ms.
    private static func criticallyDamped(_ x: inout Double, _ v: inout Double, target: Double, response: Double, dt: Double) {
        guard dt > 0, response > 0 else { return }
        let omega = 2 * Double.pi / response
        let dx = x - target
        let e = exp(-omega * dt)
        let newX = target + (dx + (v + omega * dx) * dt) * e
        let newV = (v - (v + omega * dx) * omega * dt) * e
        x = newX
        v = newV
    }

    init(config: RaceConfig, movement: MovementSource, splitUnit: DistanceUnit = .km, seed: UInt64 = 0x5241_4345) {
        self.config = config
        self.scoring = config.scoring
        self.distanceMeters = config.distanceMeters
        self.movement = movement
        self.userID = config.user.id
        self.splitUnitMeters = splitUnit.meters

        for (i, racer) in config.participants.enumerated() {
            states[racer.id] = RacerState(
                id: racer.id, distance: 0, pace: racer.handicapPaceSecPerKm,
                avgPace: racer.handicapPaceSecPerKm, finished: false, finishTime: nil,
                scoredPosition: 0, place: i + 1
            )
            splits[racer.id] = []
            if !racer.isUser {
                let personality = GhostPersonality.from(
                    archetype: Archetype.allCases[i % Archetype.allCases.count],
                    pace: racer.handicapPaceSecPerKm,
                    seed: seed &+ UInt64(i &* 7919),
                    aggression: 0.5
                )
                ghosts[racer.id] = GhostRunner(
                    racerID: racer.id, personality: personality, distanceMeters: distanceMeters
                )
            }
        }
    }

    // MARK: Tick

    func start() {
        movement.start()
        emit(.init(at: 0, kind: .start, text: startLine(), accent: .signal))
    }

    /// Integrate one frame. Called off the display link, so `dt` is 8.3ms on
    /// ProMotion and 16.6ms elsewhere — every term here is dt-correct.
    func tick(dt: Double) {
        guard !isFinished else { return }
        elapsed += dt

        let progress = min(userState.distance / distanceMeters, 1)
        movement.tick(dt: dt, raceProgress: progress)

        // 1. User.
        updateUserState()

        // 2. Ghosts, each told how far ahead the user currently is in scoring terms.
        let userScore = states[userID]?.scoredPosition ?? 0
        for (id, ghost) in ghosts {
            let myScore = states[id]?.scoredPosition ?? 0
            ghost.step(dt: dt, deficit: userScore - myScore)
            updateGhostState(id: id, ghost: ghost)
        }

        // 3. Scoring, ordering, events.
        recomputeScores()
        recomputePlaces()
        detectLeadChange()
        detectSplits()
        detectMarkers()
        detectSurges()
        sampleFinish()
        stepDisplayValues(dt: dt)
        checkClosing()
        checkFinished()
    }

    // MARK: State

    var userState: RacerState { states[userID] ?? RacerState(id: userID, distance: 0, pace: 0, avgPace: 0, finished: false, finishTime: nil, scoredPosition: 0, place: 1) }

    func state(_ id: UUID) -> RacerState { states[id] ?? userState }

    /// Signed metres: positive means the user is ahead of that opponent.
    /// In `.fair` scoring this is the handicap-adjusted gap, which is the whole
    /// point — a slower runner outperforming their own pace shows as `+`.
    func gap(to opponent: UUID) -> Double {
        (states[userID]?.scoredPosition ?? 0) - (states[opponent]?.scoredPosition ?? 0)
    }

    /// The gap that goes on screen as the single biggest thing: against whoever
    /// is immediately relevant — the racer directly ahead if you're chasing, or
    /// the racer directly behind if you're leading.
    var headlineGap: (opponent: UUID, meters: Double)? {
        let user = userState
        let others = states.values.filter { $0.id != userID }
        guard !others.isEmpty else { return nil }
        if user.place == 1 {
            guard let chaser = others.max(by: { $0.scoredPosition < $1.scoredPosition }) else { return nil }
            return (chaser.id, user.scoredPosition - chaser.scoredPosition)
        } else {
            let ahead = others.filter { $0.scoredPosition > user.scoredPosition }
            guard let target = ahead.min(by: { $0.scoredPosition < $1.scoredPosition }) else { return nil }
            return (target.id, user.scoredPosition - target.scoredPosition)
        }
    }

    /// A racer's trailing light, in metres relative to where the user is *now*.
    ///
    /// Everything on the lane lives in one frame of reference: world position,
    /// offset so the user's current position sits at zero. That way every trail —
    /// the user's included — has a length proportional to that racer's actual
    /// speed, and the head of each trail lands exactly on that racer's dot.
    ///
    /// Under `.fair` scoring the same thing is done with handicap-adjusted
    /// positions, so the lane shows the fair race rather than the raw one.
    /// Reuses the finish-sample buffer; no second history is kept.
    func trailOffsets(for id: UUID, seconds: Double) -> [Double] {
        guard finishSamples.count > 2,
              let racer = config.participants.first(where: { $0.id == id })
        else { return [] }

        let userNow = states[userID]?.scoredPosition ?? 0
        let cutoff = elapsed - seconds
        var out: [Double] = []
        out.reserveCapacity(Int(seconds * finishSampleHz) + 2)

        for sample in finishSamples where sample.t >= cutoff {
            guard let d = sample.distances[id] else { continue }
            let scored: Double
            switch scoring {
            case .raw:
                scored = d
            case .fair:
                scored = d - sample.t / racer.handicapPaceSecPerKm * 1000
            }
            out.append(scored - userNow)
        }
        return out
    }

    var remainingMeters: Double { max(0, distanceMeters - userState.distance) }
    var isClosing: Bool { enteredClosing }
    /// 0…1 through the final 200m. Drives the heartbeat and the bloom.
    var closingProgress: Double {
        guard enteredClosing else { return 0 }
        return min(max(1 - remainingMeters / 200, 0), 1)
    }

    // MARK: Internals

    private func updateUserState() {
        var s = states[userID] ?? userState
        guard !s.finished else { return }
        s.distance = min(movement.distance, distanceMeters)
        s.pace = movement.speed > 0.3 ? 1000 / movement.speed : 0
        s.avgPace = s.distance > 20 ? elapsed / (s.distance / 1000) : config.user.handicapPaceSecPerKm
        if s.distance >= distanceMeters, !s.finished {
            s.finished = true
            // Interpolate the crossing off the last known speed.
            let overshoot = movement.distance - distanceMeters
            s.finishTime = elapsed - (movement.speed > 0 ? overshoot / movement.speed : 0)
            finishedOrder.append(userID)
            if firstFinishAt == nil { firstFinishAt = s.finishTime ?? elapsed }
        }
        states[userID] = s
    }

    private func updateGhostState(id: UUID, ghost: GhostRunner) {
        var s = states[id] ?? userState
        guard !s.finished else { return }
        s.distance = ghost.distance
        s.pace = ghost.currentPaceSecPerKm
        s.avgPace = s.distance > 20 ? elapsed / (s.distance / 1000) : s.pace
        if ghost.finished, !s.finished {
            s.finished = true
            s.finishTime = ghost.finishTime ?? elapsed
            finishedOrder.append(id)
            if firstFinishAt == nil { firstFinishAt = s.finishTime ?? elapsed }
            if let place = finishedOrder.firstIndex(of: id).map({ $0 + 1 }),
               let racer = config.participants.first(where: { $0.id == id }) {
                emit(.init(at: elapsed, kind: .finish(by: id, place: place),
                           text: "\(racer.displayName) is in.", accent: .them))
            }
        }
        states[id] = s
    }

    /// Handicap racing, in one function.
    ///
    /// `.raw` — metres covered, full stop.
    /// `.fair` — metres ahead of where *your own* recent pace says you should be.
    ///   A 12:00/mi runner who is 30m up on their own expectation beats a
    ///   7:00/mi runner who is 10m up on theirs, and deserves to.
    private func recomputeScores() {
        for (id, var s) in states {
            switch scoring {
            case .raw:
                s.scoredPosition = s.distance
            case .fair:
                guard let racer = config.participants.first(where: { $0.id == id }) else { continue }
                let referenceTime = s.finished ? (s.finishTime ?? elapsed) : elapsed
                let expected = referenceTime / racer.handicapPaceSecPerKm * 1000
                s.scoredPosition = s.distance - expected
                // Once finished, the score freezes at the line — otherwise a
                // finisher's expectation keeps growing and they slide backwards
                // through the standings while standing still.
                if s.finished { s.scoredPosition = distanceMeters - expected }
            }
            states[id] = s
        }
    }

    private func recomputePlaces() {
        // Finishers are ordered by when they finished; everyone still running is
        // ordered behind them by score.
        let running = states.values
            .filter { !$0.finished }
            .sorted { $0.scoredPosition > $1.scoredPosition }
        var place = 1
        for id in finishedOrder {
            states[id]?.place = place
            place += 1
        }
        for s in running {
            states[s.id]?.place = place
            place += 1
        }
    }

    private func detectLeadChange() {
        let ranked = states.values.sorted { $0.scoredPosition > $1.scoredPosition }
        guard let top = ranked.first else { return }
        let second = ranked.dropFirst().first

        // Must be clear by a real margin, and hold it, before it counts.
        let margin = top.scoredPosition - (second?.scoredPosition ?? -.infinity)
        guard margin >= leadMarginMeters else {
            candidateLeader = nil
            return
        }

        if top.id != currentLeader {
            if candidateLeader != top.id {
                candidateLeader = top.id
                candidateSince = elapsed
            } else if elapsed - candidateSince >= leadHoldSeconds {
                let previous = currentLeader
                currentLeader = top.id
                candidateLeader = nil
                guard previous != nil else { return }   // opening lead isn't a "change"

                let userGained = top.id == userID
                onLeadChange?(top.id, userGained)
                if userGained {
                    emit(.init(at: elapsed, kind: .leadTaken(by: top.id),
                               text: "You took the lead.", accent: .you))
                } else if let racer = config.participants.first(where: { $0.id == top.id }) {
                    emit(.init(at: elapsed, kind: .leadTaken(by: top.id),
                               text: "\(racer.displayName) is through.", accent: .them))
                }
            }
        } else {
            candidateLeader = nil
        }
    }

    private func detectSplits() {
        let s = userState
        let marker = Double(nextSplitIndex) * splitUnitMeters
        guard s.distance >= marker, marker <= distanceMeters else { return }
        let previous = splits[userID]?.last?.time ?? 0
        let segmentTime = elapsed - previous
        let split = Split(
            index: nextSplitIndex, time: elapsed,
            paceSecPerKm: segmentTime / (splitUnitMeters / 1000)
        )
        splits[userID, default: []].append(split)
        onSplit?(nextSplitIndex, segmentTime)
        emit(.init(at: elapsed, kind: .split(km: nextSplitIndex, time: segmentTime),
                   text: "\(nextSplitIndex)K — \(Fmt.clock(segmentTime))", accent: .signal))
        nextSplitIndex += 1

        // Ghosts get splits recorded too, for the post-race comparison.
        for (id, _) in ghosts {
            guard let gs = states[id], gs.distance >= marker else { continue }
            if (splits[id]?.count ?? 0) < nextSplitIndex - 1 {
                let prev = splits[id]?.last?.time ?? 0
                splits[id, default: []].append(Split(
                    index: nextSplitIndex - 1, time: elapsed,
                    paceSecPerKm: (elapsed - prev) / (splitUnitMeters / 1000)
                ))
            }
        }
    }

    private func detectMarkers() {
        for marker in [1000, 800, 400, 200] where !announcedMarkers.contains(marker) {
            guard remainingMeters <= Double(marker), remainingMeters > 0,
                  distanceMeters > Double(marker) * 1.3 else { continue }
            announcedMarkers.insert(marker)
            emit(.init(at: elapsed, kind: .distanceToGo(meters: marker),
                       text: "\(marker)m to go.", accent: marker <= 200 ? .signal : .neutral))
        }
    }

    /// A surge is a *sustained* move, not a noisy second. Compared against the
    /// runner's own recent average so a fast runner cruising isn't called a surge.
    private func detectSurges() {
        // Nothing is a "surge" in the first ninety seconds. Everyone is still
        // settling into pace, the comparison windows are barely populated, and
        // "Karim surged" twenty-two seconds into a 5K is the ticker crying wolf
        // on the first line it ever prints.
        guard elapsed > 90 else { return }

        for (id, _) in ghosts {
            guard let s = states[id], !s.finished, s.pace > 0 else { continue }
            var history = paceHistory[id, default: []]
            history.append((elapsed, s.pace))
            history.removeAll { elapsed - $0.t > 20 }
            paceHistory[id] = history
            guard history.count > 40, elapsed - (lastSurgeCall[id] ?? -60) > 25 else { continue }

            let recent = history.suffix(while: { elapsed - $0.t < 8 })
            let earlier = history.prefix(while: { elapsed - $0.t > 12 })
            guard recent.count > 10, earlier.count > 10 else { continue }
            let recentAvg = recent.map(\.pace).reduce(0, +) / Double(recent.count)
            let earlierAvg = earlier.map(\.pace).reduce(0, +) / Double(earlier.count)
            guard let racer = config.participants.first(where: { $0.id == id }) else { continue }

            // Lower pace number = faster.
            if recentAvg < earlierAvg * 0.972 {
                lastSurgeCall[id] = elapsed
                emit(.init(at: elapsed, kind: .surge(by: id),
                           text: "\(racer.displayName) surged.", accent: .them))
            } else if recentAvg > earlierAvg * 1.035 {
                lastSurgeCall[id] = elapsed
                emit(.init(at: elapsed, kind: .fade(by: id),
                           text: "\(racer.displayName) is coming back to you.", accent: .you))
            }
        }
    }

    /// Sample the line at 60Hz through the closing seconds. The photo finish is
    /// only honest if it's drawn from this.
    ///
    /// The window is anchored to the **first** crossing, not to the end of the
    /// race. Previously this kept a rolling nine seconds and trimmed to the end,
    /// so in any race where the field finished more than nine seconds apart the
    /// winner's crossing had already been discarded by the time the last runner
    /// came in — and the film was reconstructed from samples where they stood
    /// motionless on the line, printing one solid slab across the frame.
    private func sampleFinish() {
        // Once the race is decided there is nothing left to photograph.
        if let first = firstFinishAt, elapsed > first + 4 { return }
        guard elapsed - lastFinishSampleAt >= 1 / finishSampleHz else { return }
        lastFinishSampleAt = elapsed
        finishSamples.append(FinishSample(
            t: elapsed,
            distances: states.mapValues(\.distance)
        ))

        // Stop trimming the moment anybody crosses: everything from here is the
        // picture.
        guard firstFinishAt == nil else { return }
        // Keep a rolling window until the race ends; then it's the record.
        //
        // Trimmed in batches, not one at a time. `removeFirst()` on an Array is
        // O(n) — at 60Hz with a 540-sample window that was shuffling half a
        // million elements a second, every second of every race, each carrying a
        // dictionary's worth of ARC traffic. Dropping a chunk at a time makes it
        // amortised O(1) for the same memory ceiling.
        if let first = finishSamples.first, elapsed - first.t > finishSampleWindow * 1.5 {
            let cutoff = elapsed - finishSampleWindow
            if let keepFrom = finishSamples.firstIndex(where: { $0.t >= cutoff }), keepFrom > 0 {
                finishSamples.removeFirst(keepFrom)
            }
        }
    }

    private func checkClosing() {
        guard !enteredClosing, remainingMeters <= 200, remainingMeters > 0 else { return }
        enteredClosing = true
        onEnterClosing?()
    }

    private func checkFinished() {
        guard !isFinished, states.values.allSatisfy(\.finished) else { return }
        isFinished = true
        movement.stop()
        onFinish?()
    }

    private func emit(_ event: RaceEvent) { onEvent?(event) }

    private func startLine() -> String {
        switch config.mode {
        case .ghost: "You against last Tuesday."
        case .headToHead: config.opponents.first.map { "\($0.displayName) is on the line." } ?? "Go."
        case .group: "\(config.participants.count) on the line."
        case .league: "League race. Points on the table."
        }
    }

    // MARK: Result

    func makeResult(baselinePace: Double, isPR: Bool) -> RaceResult {
        // Under fair scoring the order is by handicap-adjusted finish, not raw time.
        let order: [UUID] = {
            switch scoring {
            case .raw:
                return finishedOrder
            case .fair:
                return config.participants
                    .map(\.id)
                    .sorted { a, b in
                        (states[a]?.scoredPosition ?? 0) > (states[b]?.scoredPosition ?? 0)
                    }
            }
        }()
        return RaceResult(
            config: config,
            finishedAt: Date(),
            order: order,
            times: states.mapValues { $0.finishTime ?? elapsed },
            splits: splits,
            finishSamples: finishSamples,
            baselinePaceSecPerKm: baselinePace,
            isPersonalRecord: isPR
        )
    }
}

private extension Array {
    func suffix(while predicate: (Element) -> Bool) -> [Element] {
        var out: [Element] = []
        for e in reversed() {
            if predicate(e) { out.append(e) } else { break }
        }
        return out.reversed()
    }
}
