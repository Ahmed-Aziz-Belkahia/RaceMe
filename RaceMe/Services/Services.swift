import Foundation

/// The seam.
///
/// There is no backend, no auth, and no database in this build — but nothing in
/// the UI knows that. Every mock below sits behind a protocol, so a real service
/// drops in by changing one line in `AppServices` and the views never find out.

// MARK: - Protocols

protocol RacerDirectory: Sendable {
    /// People you can race right now.
    func availableOpponents(near paceSecPerKm: Double, count: Int) async throws -> [Racer]
    /// Your friends, whether or not they're running.
    func friends() async throws -> [Racer]
    func racer(id: UUID) async throws -> Racer?
}

protocol LeaderboardService: Sendable {
    func board(_ scope: LeaderboardScope, user: Racer) async throws -> [LeaderboardEntry]
    func league(user: Racer) async throws -> League
    func submit(result: RaceResult, points: Int) async throws
}

protocol RaceHistoryService: Sendable {
    func recent(limit: Int) async throws -> [RaceResult]
    func save(_ result: RaceResult) async throws
    /// The user's own best previous run over this distance, replayed as a ghost.
    func ghost(for distanceMeters: Double, user: Racer) async throws -> Racer?
    func baselinePace(for distanceMeters: Double, user: Racer) async throws -> Double
}

protocol SpectatorService: Sendable {
    /// Races currently in progress that anyone can watch. Never returns empty —
    /// an empty Live now strip is worse social proof than no strip at all.
    func liveRaces() async -> [LiveRace]
    func react(to raceID: UUID, from handle: String) async
}

protocol SubscriptionService: Sendable {
    func plans() async -> [SubscriptionPlan]
    func purchase(_ plan: SubscriptionPlan) async throws -> Bool
    func restore() async throws -> Bool
}

struct SubscriptionPlan: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Displayed large.
    let headlinePrice: String
    /// Displayed small underneath, always — an annual price without its
    /// per-month equivalent is the kind of thing that costs you a review.
    let perMonthNote: String?
    let trialDays: Int?
    let isBestValue: Bool
}

// MARK: - Errors
//
// Every message says what happened and what to do. No apologies, nothing vague.

enum RaceMeError: LocalizedError, Sendable {
    case noOpponentsAvailable
    case raceAlreadyRunning
    case challengeExpired
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .noOpponentsAvailable:
            "Nobody's within range of your pace right now."
        case .raceAlreadyRunning:
            "You're already in a race."
        case .challengeExpired:
            "That challenge already ran."
        case .purchaseFailed:
            "The purchase didn't go through."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noOpponentsAvailable:
            "Race your own ghost instead — it's the same loop, and you'll have a time to defend."
        case .raceAlreadyRunning:
            "Finish or end it, then start this one."
        case .challengeExpired:
            "Start the same race yourself and send it back."
        case .purchaseFailed:
            "Nothing was charged. Try again, or keep going on the free plan."
        }
    }
}

// MARK: - Mock data

enum MockRoster {
    /// Names deliberately span registers and regions. Nobody in this app is
    /// called "Runner 1".
    static let names: [(String, String)] = [
        ("Karim", "karim.o"), ("Noor", "noor_h"), ("Dee", "deeruns"),
        ("Tobi", "tobi.k"), ("Mara", "mara.v"), ("Ines", "ines__"),
        ("Sam", "samwr"), ("Yusuf", "yusufa"), ("Kit", "kitlane"),
        ("Bea", "beatrx"), ("Ravi", "ravi.p"), ("Elin", "elin.s"),
        ("Jonah", "jonahq"), ("Alix", "alixv"), ("Priya", "priya.r"),
        ("Otto", "ottow"), ("Nadia", "nadia.b"), ("Cass", "casst"),
        ("Milo", "milo.j"), ("Zeynep", "zey.n"),
    ]

    static func racer(index: Int, paceSecPerKm: Double, seed: UInt64 = 7) -> Racer {
        var rng = Rng(seed: seed &+ UInt64(index &* 104_729))
        let (name, handle) = names[index % names.count]
        return Racer(
            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index)) ?? UUID(),
            handle: handle,
            displayName: name,
            mark: AvatarMark.allCases[index % AvatarMark.allCases.count],
            isUser: false,
            handicapPaceSecPerKm: paceSecPerKm,
            pb5K: paceSecPerKm * 5 * rng.range(0.94, 0.99),
            careerWins: Int(rng.range(3, 60)),
            careerLosses: Int(rng.range(2, 45)),
            colorIndex: index
        )
    }
}

// MARK: - Mock implementations

struct MockRacerDirectory: RacerDirectory {
    func availableOpponents(near paceSecPerKm: Double, count: Int) async throws -> [Racer] {
        var rng = Rng(seed: 0xA11CE)
        guard count > 0 else { throw RaceMeError.noOpponentsAvailable }
        return (0..<count).map { i in
            MockRoster.racer(
                index: i,
                paceSecPerKm: paceSecPerKm * rng.range(0.9, 1.12),
                seed: UInt64(i) &+ 31
            )
        }
    }

    func friends() async throws -> [Racer] {
        (0..<8).map { MockRoster.racer(index: $0, paceSecPerKm: 300 + Double($0) * 11) }
    }

    func racer(id: UUID) async throws -> Racer? {
        (0..<20).map { MockRoster.racer(index: $0, paceSecPerKm: 300) }.first { $0.id == id }
    }
}

actor MockLeaderboardService: LeaderboardService {
    private var submittedPoints: [UUID: Int] = [:]

    func board(_ scope: LeaderboardScope, user: Racer) async throws -> [LeaderboardEntry] {
        var rng = Rng(seed: scope == .friends ? 0xF12E : scope == .global ? 0x610B : 0x1EA6)
        let size = scope == .friends ? 9 : scope == .global ? 40 : League.size
        var entries: [LeaderboardEntry] = []

        // Place the user honestly rather than always near the top. A leaderboard
        // that flatters is a leaderboard nobody climbs.
        let userRank = scope == .friends ? 4 : scope == .global ? 18 : 9
        var points = Int(rng.range(560, 720))

        for rank in 1...size {
            let isUser = rank == userRank
            let racer = isUser ? user : MockRoster.racer(index: rank, paceSecPerKm: 260 + Double(rank) * 7)
            let bonus = submittedPoints[racer.id] ?? 0
            entries.append(LeaderboardEntry(
                id: racer.id,
                rank: rank,
                previousRank: rank + Int(rng.range(-2, 3)),
                racer: racer,
                points: points + (isUser ? bonus : 0),
                racesThisWeek: Int(rng.range(1, 7))
            ))
            points -= Int(rng.range(6, 26))
        }
        return entries
    }

    func league(user: Racer) async throws -> League {
        let entries = try await board(.league, user: user)
        return League(
            id: UUID(),
            tier: .silver,
            entries: entries,
            resetsAt: Self.nextMonday()
        )
    }

    func submit(result: RaceResult, points: Int) async throws {
        submittedPoints[result.userID, default: 0] += points
    }

    /// The deadline that makes the whole league work.
    nonisolated static func nextMonday(from date: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let next = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, weekday: 2),
            matchingPolicy: .nextTime
        )
        return next ?? date.addingTimeInterval(7 * 86400)
    }
}

actor MockRaceHistoryService: RaceHistoryService {
    private var results: [RaceResult] = []

    func recent(limit: Int) async throws -> [RaceResult] {
        Array(results.sorted { $0.finishedAt > $1.finishedAt }.prefix(limit))
    }

    func save(_ result: RaceResult) async throws {
        results.append(result)
    }

    /// Ghost racing. Your own past run, at its real pace, as an opponent.
    /// This is what kills cold start: a user with zero friends still has the
    /// entire loop available on day one.
    func ghost(for distanceMeters: Double, user: Racer) async throws -> Racer? {
        let previous = results
            .filter { abs($0.config.distanceMeters - distanceMeters) < 1 }
            .min { $0.userTime < $1.userTime }

        let pace = previous?.userPace ?? user.handicapPaceSecPerKm * 1.01
        let when = previous.map { Self.relativeDay($0.finishedAt) } ?? "last Tuesday"

        return Racer(
            id: UUID(uuidString: "00000000-0000-4000-8000-0000000000FF") ?? UUID(),
            handle: "ghost",
            displayName: "You, \(when)",
            mark: user.mark,
            isUser: false,
            handicapPaceSecPerKm: pace,
            colorIndex: 1
        )
    }

    func baselinePace(for distanceMeters: Double, user: Racer) async throws -> Double {
        let matching = results.filter { abs($0.config.distanceMeters - distanceMeters) < 1 }
        guard !matching.isEmpty else { return user.handicapPaceSecPerKm }
        return matching.map(\.userPace).reduce(0, +) / Double(matching.count)
    }

    nonisolated private static func relativeDay(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case 0: return "this morning"
        case 1: return "yesterday"
        case 2...6:
            let f = DateFormatter(); f.dateFormat = "EEEE"
            return "last \(f.string(from: date))"
        default: return "\(days) days ago"
        }
    }
}

struct MockSubscriptionService: SubscriptionService {
    func plans() async -> [SubscriptionPlan] {
        [
            SubscriptionPlan(
                id: "annual", title: "Annual", headlinePrice: "£39.99",
                perMonthNote: "£3.33 / month", trialDays: 7, isBestValue: true
            ),
            SubscriptionPlan(
                id: "monthly", title: "Monthly", headlinePrice: "£5.99",
                perMonthNote: nil, trialDays: nil, isBestValue: false
            ),
            SubscriptionPlan(
                id: "lifetime", title: "Lifetime", headlinePrice: "£89.99",
                perMonthNote: "once", trialDays: nil, isBestValue: false
            ),
        ]
    }

    func purchase(_ plan: SubscriptionPlan) async throws -> Bool {
        try? await Task.sleep(for: .milliseconds(700))
        return true
    }

    func restore() async throws -> Bool {
        try? await Task.sleep(for: .milliseconds(400))
        return false
    }
}

// MARK: - Container

/// One place to swap mocks for the real thing.
@MainActor
final class AppServices {
    let directory: RacerDirectory
    let leaderboards: LeaderboardService
    let history: RaceHistoryService
    let spectator: SpectatorService
    let subscriptions: SubscriptionService

    init(
        directory: RacerDirectory = MockRacerDirectory(),
        leaderboards: LeaderboardService = MockLeaderboardService(),
        history: RaceHistoryService = MockRaceHistoryService(),
        spectator: SpectatorService,
        subscriptions: SubscriptionService = MockSubscriptionService()
    ) {
        self.directory = directory
        self.leaderboards = leaderboards
        self.history = history
        self.spectator = spectator
        self.subscriptions = subscriptions
    }
}
