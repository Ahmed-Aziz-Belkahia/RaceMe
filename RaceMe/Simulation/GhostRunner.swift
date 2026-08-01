import Foundation

/// A simulated opponent that behaves like a person rather than a constant.
///
/// The requirements this has to satisfy, and how:
///
/// - **Realistic split behaviour** — a shaped pace curve per personality, not a
///   flat target. Runners go out too hard, settle, and drift.
/// - **Fatigue drift** — a superlinear slowdown term over race progress.
/// - **A kick in the last 400** — ramped, and stronger for runners with a kick.
/// - **Randomness** — an Ornstein–Uhlenbeck process, so noise is *correlated*
///   over time. White noise reads as a glitch; correlated noise reads as a body
///   finding and losing rhythm.
/// - **They have to trade the lead.** A gap that only grows is boring and reads
///   as fake. Handled by pack response — with a deadzone, a lag, and a fade-out
///   late in the race so it never reads as a servo pulling them back to you.
struct GhostPersonality: Sendable {
    /// Seconds per km they'd hold on a good day for this distance.
    var basePaceSecPerKm: Double
    /// 0…1. How much they fall apart late.
    var fatigue: Double
    /// 0…1. How much they have left for the final 400.
    var kick: Double
    /// 0…1. How often, and how hard, they throw in a move.
    var surgeAppetite: Double
    /// 0…1. How much they react to the user's position.
    var packResponse: Double
    /// Multiplies the opening / middle / closing thirds. Frontrunners go out fast.
    var shape: (opening: Double, middle: Double, close: Double)
    var seed: UInt64

    static func from(archetype: Archetype, pace: Double, seed: UInt64, aggression: Double = 0.5) -> GhostPersonality {
        var rng = Rng(seed: seed)
        return GhostPersonality(
            basePaceSecPerKm: pace,
            fatigue: rng.range(0.25, 0.75) * (1.1 - aggression * 0.3),
            kick: rng.range(0.3, 0.9) * (0.7 + aggression * 0.5),
            surgeAppetite: rng.range(0.25, 0.85),
            packResponse: rng.range(0.45, 0.85),
            shape: archetype.paceShape,
            seed: seed
        )
    }
}

/// Integrates one ghost forward in time. Owns only its own state — the engine
/// tells it where everyone else is.
final class GhostRunner {
    let racerID: UUID
    var personality: GhostPersonality

    private(set) var distance: Double = 0
    private(set) var currentPaceSecPerKm: Double
    private(set) var finished = false
    private(set) var finishTime: Double?

    private var rng: Rng
    /// Correlated pace noise, in fractional speed.
    private var noise: Double = 0
    /// Filtered pack response, in fractional speed. Filtered so the ghost
    /// *eases* into a reaction over seconds rather than snapping to it.
    private var packTerm: Double = 0

    // Surge state machine.
    private var surgeRemaining: Double = 0
    private var surgeAmplitude: Double = 0
    private var nextSurgeAt: Double

    private let distanceMeters: Double
    private var elapsed: Double = 0

    /// The user is *inside* the noise budget of the ghost's decision-making, not
    /// outside it. Recomputed each tick by the engine.
    private var relativeDeficit: Double = 0

    init(racerID: UUID, personality: GhostPersonality, distanceMeters: Double) {
        self.racerID = racerID
        self.personality = personality
        self.distanceMeters = distanceMeters
        self.currentPaceSecPerKm = personality.basePaceSecPerKm
        var r = Rng(seed: personality.seed)
        // First move usually comes somewhere in the first third.
        self.nextSurgeAt = r.range(0.12, 0.34)
        self.rng = r
    }

    /// - Parameter deficit: metres the *user* is ahead of this ghost, in scoring
    ///   terms. Positive means the ghost is behind and, if it has any pride, will
    ///   do something about it.
    func step(dt: Double, deficit: Double) {
        guard !finished else { return }
        elapsed += dt
        relativeDeficit = deficit

        let progress = min(distance / distanceMeters, 1)

        // 1. Shaped base pace across the three thirds of the race.
        let shapeMultiplier: Double = {
            let s = personality.shape
            if progress < 0.33 {
                return lerp(s.opening, s.middle, progress / 0.33)
            } else if progress < 0.72 {
                return lerp(s.middle, s.middle, (progress - 0.33) / 0.39)
            } else {
                return lerp(s.middle, s.close, (progress - 0.72) / 0.28)
            }
        }()

        // 2. Fatigue. Superlinear — the wheels come off late, not evenly.
        let fatigueLoss = personality.fatigue * 0.075 * pow(progress, 1.9)

        // 3. Kick. Ramps in over the final 400m, or the final 12% for short races.
        let kickWindow = min(400.0, distanceMeters * 0.12)
        let remaining = distanceMeters - distance
        let kickRamp = remaining < kickWindow ? (1 - remaining / kickWindow) : 0
        let kickGain = personality.kick * 0.085 * pow(kickRamp, 0.7)

        // 4. Correlated noise. tau ≈ 9s: rhythm found and lost over roughly the
        //    length of a breathing cycle block, not frame to frame.
        let tau = 9.0
        let sigma = 0.016 + personality.surgeAppetite * 0.008
        noise += (-noise / tau) * dt + sigma * sqrt(dt) * rng.gaussian()
        noise = min(max(noise, -0.05), 0.05)

        // 5. Surges. A real move: 18–40s at 2–5% above pace, then a small
        //    recovery cost that shows up as fatigue afterwards.
        if surgeRemaining > 0 {
            surgeRemaining -= dt
            if surgeRemaining <= 0 {
                // Paid for. Brief dip below par after a hard move.
                noise -= surgeAmplitude * 0.45
            }
        } else if progress >= nextSurgeAt && progress < 0.95 {
            surgeRemaining = rng.range(18, 40)
            surgeAmplitude = rng.range(0.02, 0.05) * (0.5 + personality.surgeAppetite)
            nextSurgeAt = progress + rng.range(0.18, 0.4)
        }
        let surgeTerm = surgeRemaining > 0 ? surgeAmplitude : 0

        // 6. Pack response — the part that makes leads actually trade.
        //
        //    Deadzone: nothing under 8m. Runners don't react to a stride.
        //    Saturating: tanh, so a 200m deficit doesn't produce a 200m reaction.
        //    Fading: authority drops to ~15% over the last quarter, so the finish
        //      is decided by legs and not by the rubber band.
        //    Lagged: eased through a 6s first-order filter below, because a
        //      runner takes several seconds to respond to being passed.
        let deadzone = 8.0
        let effective = abs(deficit) < deadzone ? 0 : (deficit - deadzone * (deficit < 0 ? -1 : 1))
        let authority = progress < 0.75 ? 1.0 : lerp(1.0, 0.15, (progress - 0.75) / 0.25)
        let targetPack = tanh(effective / 45) * personality.packResponse * 0.045 * authority
        packTerm += (targetPack - packTerm) * min(1, dt / 6.0)

        // Combine into a speed multiplier. Everything above is fractional speed;
        // pace is its reciprocal.
        let speedMultiplier = 1
            / shapeMultiplier
            - fatigueLoss
            + kickGain
            + noise
            + surgeTerm
            + packTerm

        let baseSpeed = 1000 / personality.basePaceSecPerKm   // m/s
        let speed = max(0.4, baseSpeed * max(0.55, speedMultiplier))

        currentPaceSecPerKm = 1000 / speed
        distance += speed * dt

        if distance >= distanceMeters {
            // Interpolate the exact crossing rather than clamping to the frame —
            // this is what makes a 0.3s photo finish honest.
            let overshoot = distance - distanceMeters
            distance = distanceMeters
            finishTime = elapsed - overshoot / speed
            finished = true
        }
    }

    /// Used by the taste race and by ghost mode, where the outcome is known in
    /// advance and the *feel* is what matters.
    func forceFinishIfNeeded(at elapsed: Double) {
        guard !finished, distance >= distanceMeters else { return }
        finishTime = elapsed
        finished = true
    }
}

@inline(__always)
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * min(max(t, 0), 1)
}
