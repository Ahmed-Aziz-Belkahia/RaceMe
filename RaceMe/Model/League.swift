import Foundation
import SwiftUI

// MARK: - Leaderboards

enum LeaderboardScope: String, CaseIterable, Identifiable, Sendable {
    case friends, global, league
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friends: "Friends"
        case .global: "Global"
        case .league: "League"
        }
    }
    var emptyLine: String {
        switch self {
        case .friends: "Nobody to beat yet. Send a challenge link and that changes in one tap."
        case .global: "The board is still warming up. Race once and you're on it."
        case .league: "Your bracket opens Monday. Race this week to be seeded."
        }
    }
    var emptyAction: String {
        switch self {
        case .friends: "Invite someone"
        case .global: "Race now"
        case .league: "Race now"
        }
    }
}

struct LeaderboardEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var rank: Int
    var previousRank: Int
    var racer: Racer
    /// Points this period. Wins, margins, and racing above your handicap all pay.
    var points: Int
    var racesThisWeek: Int
    var isUser: Bool { racer.isUser }

    var movement: Int { previousRank - rank }
}

// MARK: - Weekly league

/// Brackets of twenty. Top five promote, bottom five relegate, resets Monday.
///
/// This exists to manufacture a deadline every week, which is the closest thing
/// to a retention cheat code there is. The user always knows exactly how many
/// races stand between them and moving up.
struct League: Identifiable, Sendable {
    let id: UUID
    var tier: Tier
    var entries: [LeaderboardEntry]
    var resetsAt: Date

    enum Tier: Int, CaseIterable, Codable, Sendable, Comparable {
        case bronze = 0, silver, gold, track, elite

        static func < (l: Tier, r: Tier) -> Bool { l.rawValue < r.rawValue }

        var name: String {
            switch self {
            case .bronze: "Bronze"
            case .silver: "Silver"
            case .gold: "Gold"
            case .track: "Track"
            case .elite: "Elite"
            }
        }
        /// Tiers are told apart by *tint of the chalk*, not by adding new hues —
        /// only the top tier gets to touch signal yellow, and only ever once
        /// on screen.
        var tint: Color {
            switch self {
            case .bronze: Track.chalk.opacity(0.45)
            case .silver: Track.chalk.opacity(0.7)
            case .gold: Track.chalk
            case .track: Track.them
            case .elite: Track.signal
            }
        }
        var next: Tier? { Tier(rawValue: rawValue + 1) }
        var previous: Tier? { Tier(rawValue: rawValue - 1) }
    }

    static let promotionCount = 5
    static let relegationCount = 5
    static let size = 20

    var userEntry: LeaderboardEntry? { entries.first(where: \.isUser) }

    func zone(for rank: Int) -> Zone {
        if rank <= Self.promotionCount { return .promotion }
        if rank > entries.count - Self.relegationCount { return .relegation }
        return .holding
    }

    enum Zone: Sendable {
        case promotion, holding, relegation

        var label: String {
            switch self {
            case .promotion: "Promotion"
            case .holding: "Holding"
            case .relegation: "Relegation"
            }
        }
        var tint: Color {
            switch self {
            case .promotion: Track.you
            case .holding: Track.chalkFaint
            case .relegation: Track.them
            }
        }
    }

    /// The deadline, stated plainly. This is the line that gets people to open
    /// the app on a Sunday night.
    func urgencyLine(now: Date = Date()) -> String {
        guard let user = userEntry else { return "Race once this week to be seeded." }
        let days = max(0, Calendar.current.dateComponents([.day], from: now, to: resetsAt).day ?? 0)
        let dayWord = days == 0 ? "Today" : days == 1 ? "1 day" : "\(days) days"
        switch zone(for: user.rank) {
        case .promotion:
            let margin = entries.first(where: { $0.rank == Self.promotionCount + 1 })?.points ?? 0
            return "\(dayWord) left. You're \(max(1, user.points - margin)) points inside promotion."
        case .holding:
            let target = entries.first(where: { $0.rank == Self.promotionCount })?.points ?? user.points
            return "\(dayWord) left. \(max(1, target - user.points + 1)) points off promotion."
        case .relegation:
            let safe = entries.first(where: { $0.rank == entries.count - Self.relegationCount })?.points ?? user.points
            return "\(dayWord) left. \(max(1, safe - user.points + 1)) points clear of the drop."
        }
    }
}

// MARK: - Points

enum Points {
    /// Racing above your own handicap pays more than simply being fast, which is
    /// what makes a Bronze bracket worth winning.
    static func award(for result: RaceResult) -> Int {
        var pts = 0
        pts += result.userWon ? 30 : 10
        // Beating your own recent form. Negative delta = faster than baseline.
        let vsBaseline = -result.deltaToBaseline
        pts += Int(max(-10, min(40, vsBaseline * 0.6)))
        if result.isPersonalRecord { pts += 25 }
        // Close racing is rewarded so nobody farms points on soft opponents.
        if abs(result.margin) < 10 { pts += 8 }
        return max(5, pts)
    }
}
