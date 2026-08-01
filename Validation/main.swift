import Foundation

// Race simulator validation harness.
//
// Compiles the *real* Rng.swift, Archetype.swift and GhostRunner.swift — no
// copies, no re-implementations — and races them thousands of times to check the
// properties the product actually depends on:
//
//   1. Races finish within a few seconds of each other.       (or they're not races)
//   2. The lead genuinely changes hands.                      (a growing gap reads as fake)
//   3. Pace curves look like running, not like a metronome.   (splits must vary, and drift late)
//   4. The kick is real and lands in the last 400m.
//   5. Handicap racing lets a slower runner beat a faster one by outperforming
//      their own baseline.
//
// Runs on any platform with a Swift toolchain — which is the point. The rest of
// the app needs a Mac; this doesn't, so the part that has to be genuinely good
// can be measured rather than assumed.
//
//   swiftc -O RaceMe/Simulation/Rng.swift RaceMe/Model/Archetype.swift \
//          RaceMe/Simulation/GhostRunner.swift Validation/main.swift -o validate
//   ./validate

// MARK: - A race between two runners

struct RaceOutcome {
    var marginSeconds: Double
    var leadChanges: Int
    var winnerIsA: Bool
    var timeA: Double
    var timeB: Double
    var splitsA: [Double]          // per-km pace, seconds/km
    var maxGapMeters: Double
    var finalGapMeters: Double
    var kickGainA: Double          // last-400 pace vs. race-average pace, seconds/km
}

/// Runs one head-to-head to the line at a fixed 60Hz step — the same rate the
/// engine samples the finish at, so margins here mean what they mean in the app.
func race(
    distance: Double,
    paceA: Double,
    paceB: Double,
    archetypeA: Archetype,
    archetypeB: Archetype,
    seed: UInt64,
    handicapA: Double? = nil,
    handicapB: Double? = nil
) -> RaceOutcome {
    let a = GhostRunner(
        racerID: UUID(),
        personality: .from(archetype: archetypeA, pace: paceA, seed: seed, aggression: 0.5),
        distanceMeters: distance
    )
    let b = GhostRunner(
        racerID: UUID(),
        personality: .from(archetype: archetypeB, pace: paceB, seed: seed &+ 7919, aggression: 0.5),
        distanceMeters: distance
    )

    let dt = 1.0 / 60.0
    var t = 0.0
    var leadChanges = 0
    var leader: Int? = nil
    var candidate: Int? = nil
    var candidateSince = 0.0
    var maxGap = 0.0

    // Scored position, matching RaceEngine: raw distance, or distance minus what
    // your own handicap pace says you should have covered by now.
    //
    // The `finished` freeze is essential and matches `RaceEngine.recomputeScores`.
    // Without it a finisher's expectation keeps growing while they stand on the
    // line, their score plummets, and everyone still running reads a false
    // thousand-metre lead and eases off. That's not a scoring detail — it's the
    // difference between handicap racing working and not.
    func score(_ r: GhostRunner, _ handicap: Double?) -> Double {
        guard let handicap else { return r.distance }
        let reference = r.finished ? (r.finishTime ?? t) : t
        return r.distance - reference / handicap * 1000
    }

    var splitsA: [Double] = []
    var nextSplit = 1
    var lastSplitTime = 0.0
    var paceSamplesLast400: [Double] = []
    var paceSamplesAll: [Double] = []

    while (!a.finished || !b.finished) && t < 20_000 {
        t += dt
        let sa = score(a, handicapA), sb = score(b, handicapB)
        a.step(dt: dt, deficit: sb - sa)
        b.step(dt: dt, deficit: sa - sb)

        // Splits and kick measurement for A.
        if !a.finished {
            paceSamplesAll.append(a.currentPaceSecPerKm)
            if distance - a.distance <= 400 { paceSamplesLast400.append(a.currentPaceSecPerKm) }
            if a.distance >= Double(nextSplit) * 1000, Double(nextSplit) * 1000 <= distance {
                splitsA.append((t - lastSplitTime) / 1.0)
                lastSplitTime = t
                nextSplit += 1
            }
        }

        let gap = abs(score(a, handicapA) - score(b, handicapB))
        maxGap = max(maxGap, gap)

        // Same hysteresis the engine uses: 1.6m clear, held for 0.9s.
        let top = score(a, handicapA) > score(b, handicapB) ? 0 : 1
        if gap >= 1.6 {
            if top != leader {
                if candidate != top { candidate = top; candidateSince = t }
                else if t - candidateSince >= 0.9 {
                    if leader != nil { leadChanges += 1 }
                    leader = top
                    candidate = nil
                }
            } else { candidate = nil }
        }
    }

    let timeA = a.finishTime ?? t
    let timeB = b.finishTime ?? t

    let avgAll = paceSamplesAll.isEmpty ? 0 : paceSamplesAll.reduce(0,+) / Double(paceSamplesAll.count)
    let avg400 = paceSamplesLast400.isEmpty ? avgAll : paceSamplesLast400.reduce(0,+) / Double(paceSamplesLast400.count)

    // Who won, decided exactly the way `RaceEngine.makeResult` decides it:
    // raw finish time under scratch, final scored position under a handicap.
    let winnerIsA: Bool = {
        guard handicapA != nil, handicapB != nil else { return timeA < timeB }
        return score(a, handicapA) > score(b, handicapB)
    }()

    return RaceOutcome(
        marginSeconds: abs(timeA - timeB),
        leadChanges: leadChanges,
        winnerIsA: winnerIsA,
        timeA: timeA, timeB: timeB,
        splitsA: splitsA,
        maxGapMeters: maxGap,
        finalGapMeters: abs(score(a, handicapA) - score(b, handicapB)),
        kickGainA: avgAll - avg400
    )
}

// MARK: - Reporting

func pct(_ n: Int, _ d: Int) -> String { String(format: "%.1f%%", Double(n) / Double(d) * 100) }
func f(_ v: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", v) }
func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s.rounded()) % 60) }

func median(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count/2] : (s[s.count/2 - 1] + s[s.count/2]) / 2
}

var failures: [String] = []
func check(_ label: String, _ passed: Bool, _ detail: String) {
    print("  \(passed ? "PASS" : "FAIL")  \(label)  \(detail)")
    if !passed { failures.append(label) }
}

print("")
print("RaceMe — race simulator validation")
print(String(repeating: "=", count: 62))

// ---------------------------------------------------------------------------
print("\n[1] Scratch 5K, evenly matched field (n=400)")

let archetypes = Archetype.allCases
var margins: [Double] = []
var changes: [Int] = []
var aWins = 0

for i in 0..<400 {
    let o = race(
        distance: 5000,
        paceA: 290,
        paceB: 292,
        archetypeA: archetypes[i % archetypes.count],
        archetypeB: archetypes[(i / 5) % archetypes.count],
        seed: UInt64(i &* 104_729 &+ 17)
    )
    margins.append(o.marginSeconds)
    changes.append(o.leadChanges)
    if o.winnerIsA { aWins += 1 }
}

let medianMargin = median(margins)
let within10 = margins.filter { $0 <= 10 }.count
let within30 = margins.filter { $0 <= 30 }.count
let tradedLead = changes.filter { $0 >= 1 }.count
let avgChanges = Double(changes.reduce(0,+)) / Double(changes.count)

print("  median margin        \(f(medianMargin))s")
print("  margins <= 10s       \(pct(within10, 400))")
print("  margins <= 30s       \(pct(within30, 400))")
print("  avg lead changes     \(f(avgChanges, 1))")
print("  A win rate           \(pct(aWins, 400))   (A is 2s/km faster on paper)")
print("")
check("races finish close", medianMargin <= 25, "median \(f(medianMargin))s, want <= 25s")
check("lead genuinely trades", Double(tradedLead) / 400 >= 0.6, "\(pct(tradedLead, 400)) of races had >= 1 lead change")
check("outcome not predetermined", (0.45...0.95).contains(Double(aWins)/400), "faster runner wins \(pct(aWins, 400))")

// ---------------------------------------------------------------------------
print("\n[2] Pace realism — a single 5K, split by split")

let sample = race(distance: 5000, paceA: 290, paceB: 292,
                  archetypeA: .closer, archetypeB: .frontrunner, seed: 42)
print("  A finish \(clock(sample.timeA))   B finish \(clock(sample.timeB))   margin \(f(sample.marginSeconds))s")
print("  A splits (s/km):     " + sample.splitsA.map { f($0, 1) }.joined(separator: "  "))
print("  max gap on the lane  \(f(sample.maxGapMeters, 1))m")
print("  lead changes         \(sample.leadChanges)")
print("")

var splitSpreads: [Double] = []
var kicks: [Double] = []
var fadeCount = 0
for i in 0..<200 {
    let o = race(distance: 5000, paceA: 290, paceB: 291,
                 archetypeA: archetypes[i % archetypes.count],
                 archetypeB: archetypes[(i / 3) % archetypes.count],
                 seed: UInt64(i &* 7717 &+ 3))
    guard o.splitsA.count >= 4 else { continue }
    splitSpreads.append((o.splitsA.max() ?? 0) - (o.splitsA.min() ?? 0))
    kicks.append(o.kickGainA)
    // Fatigue drift: is the 4th km slower than the 2nd?
    if o.splitsA[3] > o.splitsA[1] { fadeCount += 1 }
}
let medSpread = median(splitSpreads)
let medKick = median(kicks)
print("  median split spread  \(f(medSpread, 1))s between fastest and slowest km")
print("  median final-400 gain \(f(medKick, 1))s/km faster than race average")
print("  runners slower at 4K than 2K: \(pct(fadeCount, splitSpreads.count))")
print("")
check("splits vary like running", (4.0...60.0).contains(medSpread), "spread \(f(medSpread,1))s, want 4-60s")
check("kick is real and late", medKick > 1.5, "final 400 is \(f(medKick,1))s/km quicker")
check("fatigue drift present", Double(fadeCount)/Double(max(splitSpreads.count,1)) >= 0.5, "\(pct(fadeCount, splitSpreads.count)) fade")

// ---------------------------------------------------------------------------
print("\n[3] Handicap racing — 12:00/mi runner vs 7:00/mi runner (n=300)")
print("      Under fair scoring the slow runner must be able to win by beating")
print("      their own baseline. If they can't, every beginner churns in week one.")

let slowPace = 12 * 60 / 1.609344     // ~447 s/km
let fastPace = 7 * 60 / 1.609344      // ~261 s/km
var slowWins = 0
var scratchSlowWins = 0

for i in 0..<300 {
    // Archetypes are sampled independently on both sides. Pinning one archetype
    // per runner would measure the archetype pairing, not the handicap system —
    // which is the mistake the first version of this test made.
    let arcA = archetypes[i % archetypes.count]
    let arcB = archetypes[(i / archetypes.count) % archetypes.count]

    // Fair: each is scored against their own handicap.
    let fair = race(distance: 5000, paceA: slowPace, paceB: fastPace,
                    archetypeA: arcA, archetypeB: arcB,
                    seed: UInt64(i &* 31 &+ 5),
                    handicapA: slowPace, handicapB: fastPace)
    if fair.winnerIsA { slowWins += 1 }

    // Scratch: raw time. The slow runner should essentially never win.
    let scratch = race(distance: 5000, paceA: slowPace, paceB: fastPace,
                       archetypeA: arcA, archetypeB: arcB,
                       seed: UInt64(i &* 31 &+ 5))
    if scratch.winnerIsA { scratchSlowWins += 1 }
}

print("  slow runner wins, fair scoring     \(pct(slowWins, 300))")
print("  slow runner wins, scratch scoring  \(pct(scratchSlowWins, 300))")
print("")
check("handicap makes it winnable", (0.2...0.8).contains(Double(slowWins)/300),
      "\(pct(slowWins, 300)) — want a real contest, not a gift")
check("scratch still means something", Double(scratchSlowWins)/300 < 0.02,
      "\(pct(scratchSlowWins, 300)) — the faster runner should win on raw time")

// ---------------------------------------------------------------------------
print("\n[3b] Archetype fairness — no archetype may be inherently faster")
print("      Under fair scoring you race your own handicap, so an archetype that")
print("      averages faster than its own baseline is a free win. This is the")
print("      check that caught handicap racing being decided by archetype draw.")

var worstBias = 0.0
for arc in archetypes {
    // Same pace, same handicap, matched against itself — any systematic
    // deviation from the handicap is the archetype's own bias.
    var deltas: [Double] = []
    for i in 0..<60 {
        let o = race(distance: 5000, paceA: 290, paceB: 290,
                     archetypeA: arc, archetypeB: arc,
                     seed: UInt64(i &* 613 &+ 11),
                     handicapA: 290, handicapB: 290)
        deltas.append(290 * 5 - o.timeA)     // + means faster than handicap
    }
    let bias = median(deltas)
    worstBias = max(worstBias, abs(bias))
    print("  \(arc.name.padding(toLength: 16, withPad: " ", startingAt: 0))"
          + "median \(bias >= 0 ? "+" : "")\(f(bias, 1))s vs own handicap")
}
print("")
// Fatigue and the kick shift everyone off their baseline a little; what matters
// is that they shift everyone by roughly the same amount.
var spreadOfBias: [Double] = []
for arc in archetypes {
    var deltas: [Double] = []
    for i in 0..<60 {
        let o = race(distance: 5000, paceA: 290, paceB: 290,
                     archetypeA: arc, archetypeB: arc, seed: UInt64(i &* 613 &+ 11),
                     handicapA: 290, handicapB: 290)
        deltas.append(290 * 5 - o.timeA)
    }
    spreadOfBias.append(median(deltas))
}
let biasSpread = (spreadOfBias.max() ?? 0) - (spreadOfBias.min() ?? 0)
check("archetypes are equal-effort", biasSpread < 6.0,
      "worst-to-best spread \(f(biasSpread, 1))s over a 5K, want < 6s")

// ---------------------------------------------------------------------------
print("\n[3c] Matchmaking — the pace distribution the app actually draws from")
print("      Earlier passes raced hand-picked paces and never exercised this,")
print("      which is how a three-sigma opponent ten percent faster than the")
print("      user reached a screenshot.")

for (label, difficulty) in [("beginner", 0.25), ("committed", 0.7), ("won't lose", 0.92)] {
    var rng = Rng(seed: 0xFA112)
    let userPace = 290.0
    var margins: [Double] = []
    var worst = 0.0

    for i in 0..<150 {
        let opponentPace = PaceSpread.opponentPace(
            userRacePaceSecPerKm: userPace,
            difficulty: difficulty,
            intent: .tossUp,
            rng: &rng
        )
        worst = max(worst, abs(opponentPace / userPace - 1))
        let o = race(distance: 5000, paceA: userPace, paceB: opponentPace,
                     archetypeA: archetypes[i % 5], archetypeB: archetypes[(i / 5) % 5],
                     seed: UInt64(i &* 911 &+ 3))
        margins.append(o.marginSeconds)
    }
    let med = median(margins)
    let p90 = margins.sorted()[Int(Double(margins.count) * 0.9)]
    print("  \(label.padding(toLength: 12, withPad: " ", startingAt: 0))"
          + "median margin \(f(med, 1))s   90th pct \(f(p90, 1))s   "
          + "widest pace draw \(f(worst * 100, 1))%")
    check("\(label) fields race close", med <= 20 && p90 <= 55,
          "median \(f(med,1))s, p90 \(f(p90,1))s")
}

// ---------------------------------------------------------------------------
print("\n[4] Determinism — same seed must reproduce the same race")
print("      Challenge links replay the sender's ghost on someone else's phone.")

let r1 = race(distance: 5000, paceA: 290, paceB: 293, archetypeA: .kicker, archetypeB: .closer, seed: 999)
let r2 = race(distance: 5000, paceA: 290, paceB: 293, archetypeA: .kicker, archetypeB: .closer, seed: 999)
check("identical seeds, identical race", r1.timeA == r2.timeA && r1.timeB == r2.timeB,
      "\(f(r1.timeA, 4)) vs \(f(r2.timeA, 4))")

let r3 = race(distance: 5000, paceA: 290, paceB: 293, archetypeA: .kicker, archetypeB: .closer, seed: 1000)
check("different seeds, different race", r1.timeA != r3.timeA,
      "\(f(r1.timeA, 2)) vs \(f(r3.timeA, 2))")

// ---------------------------------------------------------------------------
print("\n[5] Distances hold up (400m taste race through 10K)")

for d in [400.0, 1609.344, 5000.0, 10_000.0] {
    var ms: [Double] = []
    var lc: [Int] = []
    for i in 0..<80 {
        let o = race(distance: d, paceA: 290, paceB: 292,
                     archetypeA: archetypes[i % 5], archetypeB: archetypes[(i/2) % 5],
                     seed: UInt64(i &* 137 &+ Int(d)))
        ms.append(o.marginSeconds); lc.append(o.leadChanges)
    }
    let name = d < 1000 ? "\(Int(d))m" : (d == 1609.344 ? "1 mile" : "\(Int(d/1000))K")
    print("  \(name.padding(toLength: 8, withPad: " ", startingAt: 0))"
          + "median margin \(f(median(ms), 1))s   "
          + "avg lead changes \(f(Double(lc.reduce(0,+))/Double(lc.count), 1))   "
          + "median time \(clock(median(ms.indices.map { _ in 0 }) == 0 ? median(ms) : 0))"
            .replacingOccurrences(of: "median time 0:00", with: ""))
    check("\(name) finishes close", median(ms) <= 30, "median \(f(median(ms),1))s")
}

// ---------------------------------------------------------------------------
print("\n" + String(repeating: "=", count: 62))
if failures.isEmpty {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("FAILED: \(failures.count) check(s)")
    for f in failures { print("  - \(f)") }
    exit(1)
}
