import Foundation
import SwiftUI

// MARK: - Configuration

enum RaceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// One opponent. The purest form of the product.
    case headToHead
    /// Three to six. Positions churn, which is where the drama is.
    case group
    /// Your own past run, replayed at its real pace. Kills cold start —
    /// a user with zero friends still has the full loop on day one.
    case ghost
    /// Everyone in the weekly bracket, racing the same distance asynchronously.
    case league

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headToHead: "Head to head"
        case .group: "Group"
        case .ghost: "Ghost"
        case .league: "League"
        }
    }

    var shortLabel: String {
        switch self {
        case .headToHead: "H2H"
        case .group: "GROUP"
        case .ghost: "GHOST"
        case .league: "LEAGUE"
        }
    }
}

/// How the gap on screen is computed.
enum Scoring: String, Codable, CaseIterable, Sendable {
    /// Raw metres covered. Fastest runner wins, full stop.
    case raw
    /// **Handicap racing.** The gap shown is each racer's position relative to
    /// their *own* expected pace. A 12:00/mi runner genuinely beats a 7:00/mi
    /// runner by outperforming themselves.
    ///
    /// Without this, every beginner loses every race and churns inside a week.
    /// It's the single most important retention mechanic in the app.
    case fair

    var title: String { self == .fair ? "Fair" : "Scratch" }
    var explainer: String {
        self == .fair
            ? "Everyone races their own recent pace. Beat yours by more than they beat theirs and you win."
            : "Raw distance. Fastest runner takes it."
    }
}

struct RaceConfig: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var distanceMeters: Double
    var mode: RaceMode
    var scoring: Scoring
    /// Everyone in the race, user included. The user is always index 0.
    var participants: [Racer]
    /// Set when this race arrived from a shared challenge link.
    var challengeFrom: String?

    var user: Racer { participants.first(where: \.isUser) ?? participants[0] }
    var opponents: [Racer] { participants.filter { !$0.isUser } }
    var title: String { Fmt.raceName(distanceMeters) }
}

// MARK: - Live state

/// One racer's state at one instant. Value type on purpose — the engine
/// produces a fresh immutable snapshot per tick and the view diffs against it.
struct RacerState: Identifiable, Hashable, Sendable {
    let id: UUID
    var distance: Double          // metres covered
    var pace: Double              // current, seconds per km
    var avgPace: Double           // race-to-date, seconds per km
    var finished: Bool
    var finishTime: Double?       // elapsed seconds at the line
    /// Under `.fair` scoring, metres ahead of (or behind) their own expected
    /// position. Under `.raw`, this equals `distance`.
    var scoredPosition: Double
    /// 1-based finishing order as it currently stands.
    var place: Int
}

struct RaceSnapshot: Sendable {
    var elapsed: Double
    var states: [UUID: RacerState]
    var phase: RacePhase
    /// 0…1 across the whole race, by the leader.
    var progress: Double

    func state(_ id: UUID) -> RacerState? { states[id] }
}

enum RacePhase: Equatable, Sendable {
    case staged
    case countdown(Int)      // 3, 2, 1
    case running
    /// Final 200m. Everything escalates here.
    case closing
    case finished
}

// MARK: - Events

/// The commentary ticker's source. Every event is generated from actual race
/// state, never scheduled for flavour.
struct RaceEvent: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case start
        case leadTaken(by: UUID)
        case surge(by: UUID)
        case fade(by: UUID)
        case split(km: Int, time: Double)
        case distanceToGo(meters: Int)
        case reaction(from: String)
        case finish(by: UUID, place: Int)
    }
    let id = UUID()
    let at: Double
    let kind: Kind
    let text: String
    /// Which colour the line is tinted.
    let accent: EventAccent

    /// Named `neutral` rather than `none` on purpose — a case called `none`
    /// collides with `Optional.none` at every comparison site and quietly
    /// resolves the wrong way.
    enum EventAccent: Hashable, Sendable { case neutral, you, them, signal }
}

extension RaceEvent.EventAccent {
    var color: Color {
        switch self {
        case .neutral: Track.chalkDim
        case .you: Track.you
        case .them: Track.them
        case .signal: Track.signal
        }
    }
}

// MARK: - Result

struct Split: Identifiable, Hashable, Codable, Sendable {
    var id: Int { index }
    let index: Int            // 1-based km (or mile)
    let time: Double          // cumulative elapsed at this marker
    let paceSecPerKm: Double
}

struct RaceResult: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var config: RaceConfig
    var finishedAt: Date
    /// Finishing order, first to last, by the config's scoring rule.
    var order: [UUID]
    var times: [UUID: Double]
    var splits: [UUID: [Split]]
    /// The last seconds at the line, sampled for the slit-scan. Real data.
    var finishSamples: [FinishSample]
    /// The user's own average pace for this distance before this race.
    var baselinePaceSecPerKm: Double
    var isPersonalRecord: Bool

    var userID: UUID { config.user.id }
    var userWon: Bool { order.first == userID }
    var userPlace: Int { (order.firstIndex(of: userID) ?? 0) + 1 }
    var userTime: Double { times[userID] ?? 0 }
    var userPace: Double { userTime / (config.distanceMeters / 1000) }

    /// Margin in seconds to whoever finished immediately adjacent. Signed:
    /// negative means they beat you.
    var margin: Double {
        guard order.count > 1 else { return 0 }
        let idx = order.firstIndex(of: userID) ?? 0
        let neighbour = idx == 0 ? order[1] : order[idx - 1]
        let delta = (times[neighbour] ?? 0) - userTime
        return idx == 0 ? delta : delta
    }

    /// Against their own recent form. This is what keeps the loser engaged —
    /// you can lose the race and still have run the best 5K of your month.
    var deltaToBaseline: Double {
        let baselineTime = baselinePaceSecPerKm * config.distanceMeters / 1000
        return userTime - baselineTime
    }
}

/// One frame of the finish, at the line. `distance` per racer lets the
/// slit-scan renderer work out exactly when each body crossed and how fast it
/// was moving when it did — which is what makes the smear real rather than
/// decorative.
struct FinishSample: Hashable, Codable, Sendable {
    let t: Double
    let distances: [UUID: Double]
}

// MARK: - Staged race (Home)

/// A race the app has set up and is offering. Home always has one of these,
/// chosen from the user's onboarding answers, so a new user never lands on an
/// empty screen.
struct StagedRace: Identifiable, Sendable {
    var id: UUID = UUID()
    var config: RaceConfig
    /// One line explaining why *this* race, in the app's voice.
    var rationale: String
    /// The app's honest read on how it'll go. Shown as a projection, not a promise.
    var projectedOutcome: Projection

    enum Projection: Sendable {
        case youFavoured(bySeconds: Double)
        case tooClose
        case theyFavoured(bySeconds: Double)

        var headline: String {
            switch self {
            case .youFavoured(let s): "You're favoured by \(Int(s))s"
            case .tooClose: "Too close to call"
            case .theyFavoured(let s): "They're \(Int(s))s faster on form"
            }
        }
        var accent: Color {
            switch self {
            case .youFavoured: Track.you
            case .tooClose: Track.signal
            case .theyFavoured: Track.them
            }
        }
    }
}

// MARK: - Spectating

struct LiveRace: Identifiable, Sendable {
    let id: UUID
    var config: RaceConfig
    var snapshot: RaceSnapshot
    var spectators: Int
    var startedAt: Date

    var elapsed: Double { snapshot.elapsed }
    var leaderID: UUID? {
        snapshot.states.values.max(by: { $0.scoredPosition < $1.scoredPosition })?.id
    }
}

/// A 🔥 sent by a spectator. The one deliberate emoji in the entire interface —
/// it's a gesture, not an icon.
struct Reaction: Identifiable, Sendable {
    let id = UUID()
    let from: String
    let at: Date
}
