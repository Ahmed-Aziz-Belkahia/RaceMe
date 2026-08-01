import Foundation

/// The viral loop, and about a day of work.
///
/// Any race generates a link. You share it, a friend taps it, and they land in a
/// pre-configured race with your name on it — same distance, same scoring, and
/// your pace loaded as the ghost they're chasing.
///
/// The payload is self-contained on purpose: no backend lookup, so a link works
/// the instant it's shared and keeps working if the sender goes offline.
struct Challenge: Codable, Hashable, Sendable {
    var fromName: String
    var fromHandle: String
    var distanceMeters: Double
    var scoring: Scoring
    var mode: RaceMode
    /// The sender's pace over this distance, in seconds per km. This becomes the
    /// ghost's target.
    var paceSecPerKm: Double
    /// The sender's finish time, if they've already run it. Turns a challenge
    /// into a number to beat rather than an invitation.
    var timeSeconds: Double?
    /// Deterministic ghost behaviour — the challenger's run replays the same way
    /// for everyone who opens the link.
    var seed: UInt64

    var headline: String {
        if let timeSeconds {
            "\(fromName) ran \(Fmt.raceName(distanceMeters)) in \(Fmt.clock(timeSeconds))."
        } else {
            "\(fromName) wants a \(Fmt.raceName(distanceMeters))."
        }
    }

    var subhead: String {
        scoring == .fair
            ? "Handicap race — you're both running against your own recent pace."
            : "Straight race. Fastest wins."
    }
}

enum ChallengeLink {
    static let scheme = "raceme"
    static let host = "challenge"
    /// A real build points this at a universal-link domain so the link previews
    /// and installs. The custom scheme is the local fallback.
    static let webPrefix = "https://raceme.app/c/"

    static func encode(_ challenge: Challenge) -> URL? {
        guard let data = try? JSONEncoder().encode(challenge) else { return nil }
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: webPrefix + payload)
    }

    static func decode(_ url: URL) -> Challenge? {
        let payload: String? = {
            if url.scheme == scheme, url.host == host {
                return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "c" })?.value
            }
            if url.absoluteString.hasPrefix(webPrefix) {
                return String(url.absoluteString.dropFirst(webPrefix.count))
            }
            return nil
        }()
        guard var payload else { return nil }

        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let challenge = try? JSONDecoder().decode(Challenge.self, from: data)
        else { return nil }
        return challenge
    }

    /// Turn a finished race into a challenge others can take.
    static func from(result: RaceResult, sender: RunnerProfile) -> Challenge {
        Challenge(
            fromName: sender.handle.isEmpty ? "A runner" : sender.handle,
            fromHandle: sender.handle,
            distanceMeters: result.config.distanceMeters,
            scoring: result.config.scoring,
            mode: .headToHead,
            paceSecPerKm: result.userPace,
            timeSeconds: result.userTime,
            seed: UInt64(abs(result.id.hashValue))
        )
    }

    /// The race a tapped link lands you in. Pre-configured, with their name on it.
    static func race(from challenge: Challenge, user: Racer) -> RaceConfig {
        let challenger = Racer(
            handle: challenge.fromHandle,
            displayName: challenge.fromName,
            mark: .blade,
            isUser: false,
            handicapPaceSecPerKm: challenge.paceSecPerKm,
            colorIndex: 0
        )
        return RaceConfig(
            distanceMeters: challenge.distanceMeters,
            mode: challenge.mode,
            scoring: challenge.scoring,
            participants: [user, challenger],
            challengeFrom: challenge.fromName
        )
    }

    /// Text that goes out with the link. Confident, short, no hashtags.
    static func shareText(_ challenge: Challenge) -> String {
        if let t = challenge.timeSeconds {
            return "\(Fmt.raceName(challenge.distanceMeters)) in \(Fmt.clock(t)). Your turn."
        }
        return "\(Fmt.raceName(challenge.distanceMeters)). Now."
    }
}
