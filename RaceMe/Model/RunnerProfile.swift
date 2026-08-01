import Foundation
import SwiftUI

// MARK: - Onboarding answers
//
// Every one of these is referenced by name somewhere after onboarding. An
// answer collected and never used again is a wasted screen, and a wasted screen
// is a wasted install.

/// S2. The bait option is `neverLose` — competitive users pick it and instantly
/// feel understood. It sets difficulty and the register of copy shown later.
enum SelfImage: String, Codable, CaseIterable, Sendable, Identifiable {
    case justStarting, whenIFeelLikeIt, trainingForSomething, neverLose
    var id: String { rawValue }

    var label: String {
        switch self {
        case .justStarting: "Just getting started"
        case .whenIFeelLikeIt: "I run when I feel like it"
        case .trainingForSomething: "I'm training for something"
        case .neverLose: "I don't lose"
        }
    }

    /// Feeds the ghost calibration. Higher means opponents run closer to the wire.
    var difficulty: Double {
        switch self {
        case .justStarting: 0.25
        case .whenIFeelLikeIt: 0.45
        case .trainingForSomething: 0.7
        case .neverLose: 0.92
        }
    }

    /// Copy register used across the app afterwards. `neverLose` gets talked to
    /// like a rival; `justStarting` gets talked to like a training partner.
    var voice: Voice {
        switch self {
        case .justStarting, .whenIFeelLikeIt: .encouraging
        case .trainingForSomething: .direct
        case .neverLose: .cocky
        }
    }

    enum Voice: Sendable { case encouraging, direct, cocky }
}

/// S4. Pick up to two.
enum Goal: String, Codable, CaseIterable, Sendable, Identifiable {
    case faster5K, consistency, weight, beatSomeone, somethingToLookForwardTo
    var id: String { rawValue }

    var label: String {
        switch self {
        case .faster5K: "A faster 5K"
        case .consistency: "Actually being consistent"
        case .weight: "Losing weight"
        case .beatSomeone: "Beating one specific person"
        case .somethingToLookForwardTo: "Something to look forward to"
        }
    }
}

/// S6. Framed as a commitment they're making, not a setting they're picking.
enum RaceFrequency: String, Codable, CaseIterable, Sendable, Identifiable {
    case once, twice, thrice, most
    var id: String { rawValue }

    var label: String {
        switch self {
        case .once: "Once a week"
        case .twice: "Twice a week"
        case .thrice: "Three times a week"
        case .most: "Most days"
        }
    }
    var perWeek: Int {
        switch self { case .once: 1; case .twice: 2; case .thrice: 3; case .most: 5 }
    }
}

/// S7. Drives when we ping them — before, not during.
enum RunWindow: String, Codable, CaseIterable, Sendable, Identifiable {
    case dawn, morning, lunch, evening
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dawn: "Before the sun"
        case .morning: "Morning"
        case .lunch: "Middle of the day"
        case .evening: "Evening"
        }
    }
    var clock: String {
        switch self {
        case .dawn: "5–7am"
        case .morning: "7–10am"
        case .lunch: "11am–2pm"
        case .evening: "5–9pm"
        }
    }
    var notifyHour: Int {
        switch self { case .dawn: 5; case .morning: 7; case .lunch: 11; case .evening: 17 }
    }
}

/// S9. Maps directly to which race modes surface first on Home.
enum Driver: String, Codable, CaseIterable, Sendable, Identifiable {
    case someoneAhead, someoneGaining, ownNumbers, theGroup
    var id: String { rawValue }

    var label: String {
        switch self {
        case .someoneAhead: "Someone just ahead of me"
        case .someoneGaining: "Someone gaining on me"
        case .ownNumbers: "My own numbers"
        case .theGroup: "Not letting my group down"
        }
    }

    /// The mode Home stages first for this driver.
    var preferredMode: RaceMode {
        switch self {
        case .someoneAhead, .someoneGaining: .headToHead
        case .ownNumbers: .ghost
        case .theGroup: .group
        }
    }

    /// How the simulator shapes opponents for this user. Someone motivated by
    /// being chased needs to lead and then feel it evaporate; someone motivated
    /// by chasing needs a target just out of reach for most of the race.
    var preferredScript: RaceScript {
        switch self {
        case .someoneAhead: .targetAhead
        case .someoneGaining: .pressureFromBehind
        case .ownNumbers: .evenPacing
        case .theGroup: .packChurn
        }
    }
}

/// How the field is choreographed against this user.
enum RaceScript: String, Codable, Sendable {
    case targetAhead          // an opponent sits 5–15m up until late
    case pressureFromBehind   // user leads, opponent closes hard from 60%
    case evenPacing           // metronomic, decided in the last 400
    case packChurn            // constant reordering through the field
}

// MARK: - Profile

@Observable
final class RunnerProfile: Codable, @unchecked Sendable {
    // Onboarding
    var selfImage: SelfImage = .whenIFeelLikeIt
    /// S3, seconds per mile. Collected via a drag control, not a picker.
    var comfortableMileSeconds: Double = 9 * 60 + 30
    var goals: [Goal] = []
    /// S5. Worth more retention than any feature in the MVP.
    var rivalName: String?
    var frequency: RaceFrequency = .twice
    var window: RunWindow = .morning
    var driver: Driver = .someoneAhead
    var handle: String = ""
    var mark: AvatarMark = .chevron

    // Permissions — recorded so we never fire a cold OS prompt twice.
    var notificationsAsked = false
    var notificationsGranted = false
    var locationAsked = false
    var locationGranted = false

    // Commerce
    var isSubscribed = false
    var completedOnboarding = false

    // Live stats
    var careerWins = 0
    var careerLosses = 0
    var totalRaces = 0
    var unit: DistanceUnit = .km
    /// Rolling recent-form pace. Seeded from S3, then genuinely learned from
    /// runs — which is exactly what S3's subtitle promises.
    var learnedPaceSecPerKm: Double?

    var userID = UUID()

    init() {}

    // MARK: Derived

    /// Seconds per km. Uses learned pace once we have real runs, which is the
    /// promise made under the S3 drag control: *we'll learn this from your runs anyway.*
    var handicapPaceSecPerKm: Double {
        learnedPaceSecPerKm ?? (comfortableMileSeconds / 1.609344)
    }

    /// Comfortable pace is not race pace. Runners race a 5K meaningfully faster
    /// than they jog, and the gap widens with training age.
    var race5KPaceSecPerKm: Double {
        let effortFactor = 1.0 - (0.06 + 0.05 * selfImage.difficulty)
        return handicapPaceSecPerKm * effortFactor
    }

    var current5KSeconds: Double { race5KPaceSecPerKm * 5 }

    /// Eight weeks out. Deliberately modest — 2–5% depending on training age,
    /// because a promise the app can't keep costs more in week nine than it wins
    /// in week one.
    var projected5KSeconds: Double {
        let improvement = 0.02 + 0.03 * (1 - selfImage.difficulty * 0.5)
        return current5KSeconds * (1 - improvement)
    }

    var archetype: Archetype { Archetype.derive(from: self) }

    var traits: [Trait] { Trait.derive(from: self) }

    /// Referenced on Home, in notifications, and on the paywall.
    var rivalMention: String? { rivalName?.trimmingCharacters(in: .whitespaces).nilIfEmpty }

    var record: String { "\(careerWins)\u{2013}\(careerLosses)" }

    func recordResult(_ result: RaceResult) {
        totalRaces += 1
        if result.userWon { careerWins += 1 } else { careerLosses += 1 }
        // Blend the new run into recent form. Weighted so one bad run in the
        // rain doesn't wreck a handicap, and one great one doesn't inflate it.
        let observed = result.userPace
        learnedPaceSecPerKm = learnedPaceSecPerKm.map { $0 * 0.75 + observed * 0.25 } ?? observed
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case selfImage, comfortableMileSeconds, goals, rivalName, frequency, window
        case driver, handle, mark, notificationsAsked, notificationsGranted
        case locationAsked, locationGranted, isSubscribed, completedOnboarding
        case careerWins, careerLosses, totalRaces, unit, learnedPaceSecPerKm, userID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selfImage = try c.decodeIfPresent(SelfImage.self, forKey: .selfImage) ?? .whenIFeelLikeIt
        comfortableMileSeconds = try c.decodeIfPresent(Double.self, forKey: .comfortableMileSeconds) ?? 570
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        rivalName = try c.decodeIfPresent(String.self, forKey: .rivalName)
        frequency = try c.decodeIfPresent(RaceFrequency.self, forKey: .frequency) ?? .twice
        window = try c.decodeIfPresent(RunWindow.self, forKey: .window) ?? .morning
        driver = try c.decodeIfPresent(Driver.self, forKey: .driver) ?? .someoneAhead
        handle = try c.decodeIfPresent(String.self, forKey: .handle) ?? ""
        mark = try c.decodeIfPresent(AvatarMark.self, forKey: .mark) ?? .chevron
        notificationsAsked = try c.decodeIfPresent(Bool.self, forKey: .notificationsAsked) ?? false
        notificationsGranted = try c.decodeIfPresent(Bool.self, forKey: .notificationsGranted) ?? false
        locationAsked = try c.decodeIfPresent(Bool.self, forKey: .locationAsked) ?? false
        locationGranted = try c.decodeIfPresent(Bool.self, forKey: .locationGranted) ?? false
        isSubscribed = try c.decodeIfPresent(Bool.self, forKey: .isSubscribed) ?? false
        completedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .completedOnboarding) ?? false
        careerWins = try c.decodeIfPresent(Int.self, forKey: .careerWins) ?? 0
        careerLosses = try c.decodeIfPresent(Int.self, forKey: .careerLosses) ?? 0
        totalRaces = try c.decodeIfPresent(Int.self, forKey: .totalRaces) ?? 0
        unit = try c.decodeIfPresent(DistanceUnit.self, forKey: .unit) ?? .km
        learnedPaceSecPerKm = try c.decodeIfPresent(Double.self, forKey: .learnedPaceSecPerKm)
        userID = try c.decodeIfPresent(UUID.self, forKey: .userID) ?? UUID()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selfImage, forKey: .selfImage)
        try c.encode(comfortableMileSeconds, forKey: .comfortableMileSeconds)
        try c.encode(goals, forKey: .goals)
        try c.encodeIfPresent(rivalName, forKey: .rivalName)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(window, forKey: .window)
        try c.encode(driver, forKey: .driver)
        try c.encode(handle, forKey: .handle)
        try c.encode(mark, forKey: .mark)
        try c.encode(notificationsAsked, forKey: .notificationsAsked)
        try c.encode(notificationsGranted, forKey: .notificationsGranted)
        try c.encode(locationAsked, forKey: .locationAsked)
        try c.encode(locationGranted, forKey: .locationGranted)
        try c.encode(isSubscribed, forKey: .isSubscribed)
        try c.encode(completedOnboarding, forKey: .completedOnboarding)
        try c.encode(careerWins, forKey: .careerWins)
        try c.encode(careerLosses, forKey: .careerLosses)
        try c.encode(totalRaces, forKey: .totalRaces)
        try c.encode(unit, forKey: .unit)
        try c.encodeIfPresent(learnedPaceSecPerKm, forKey: .learnedPaceSecPerKm)
        try c.encode(userID, forKey: .userID)
    }

    func asRacer() -> Racer {
        Racer(
            id: userID,
            handle: handle.isEmpty ? "you" : handle,
            displayName: "You",
            mark: mark,
            isUser: true,
            handicapPaceSecPerKm: handicapPaceSecPerKm,
            pb5K: nil,
            careerWins: careerWins,
            careerLosses: careerLosses
        )
    }
}

// MARK: - Archetype derivation
//
// The `Archetype` enum itself lives in `Model/Archetype.swift`, which imports
// nothing but Foundation so the simulation layer can be compiled and run on a
// non-Apple machine. Only the part that needs a `RunnerProfile` lives here.

extension Archetype {
    static func derive(from profile: RunnerProfile) -> Archetype {
        switch (profile.driver, profile.selfImage) {
        case (.someoneAhead, .neverLose): .kicker
        case (.someoneAhead, _): .closer
        case (.someoneGaining, _): .frontrunner
        case (.ownNumbers, _): .metronome
        case (.theGroup, .justStarting): .grinder
        case (.theGroup, _): .closer
        }
    }
}

/// Three traits, charted on the card.
struct Trait: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    /// 0…1
    let value: Double

    static func derive(from p: RunnerProfile) -> [Trait] {
        let shape = p.archetype.paceShape
        // Kick: how much faster the close is than the middle.
        let kick = clamp((shape.middle - shape.close) * 8 + 0.4)
        // Consistency: metronomes and consistency-seekers score high.
        let consistency = clamp(
            0.42
            + (p.archetype == .metronome ? 0.34 : 0)
            + (p.goals.contains(.consistency) ? 0.2 : 0)
            + Double(p.frequency.perWeek) * 0.03
        )
        // Nerve: appetite for going with a move.
        let nerve = clamp(0.3 + p.selfImage.difficulty * 0.55 + (p.rivalName != nil ? 0.12 : 0))
        return [
            Trait(name: "Kick", value: kick),
            Trait(name: "Consistency", value: consistency),
            Trait(name: "Nerve", value: nerve),
        ]
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0.08), 0.98) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
