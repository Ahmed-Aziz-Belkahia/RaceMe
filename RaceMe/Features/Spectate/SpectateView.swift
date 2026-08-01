import SwiftUI

/// Watching someone else's race, live.
///
/// Same lane, same gap, same numbers — because a spectator should see exactly
/// what the racer sees, and because building a second visualisation would be
/// building a second product. What's different is unmistakable: a marker that
/// says you're watching, whose race it is, and one thing to do about it.
///
/// Tapping sends a 🔥 that lands on the runner's own screen. Reactions arriving
/// mid-race is one of the strongest retention mechanics a racing app has — it
/// makes running feel watched.
struct SpectateView: View {
    @Bindable var app: AppState
    let race: LiveRace
    var onClose: () -> Void

    @Environment(\.motion) private var motion
    @State private var sentReactions: [Reaction] = []
    @State private var sendCount = 0

    private var engine: RaceEngine? { app.liveRaces.engine(for: race.id) }

    /// The race's featured runner takes the "user" slot of its config, so the
    /// lane can render it with the same code path. Their colour stays cool —
    /// warm rust is reserved for *you*, and you aren't in this race.
    private var featured: Racer { race.config.user }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                spectatingMarker
                    .padding(.top, 8)

                Spacer(minLength: 10)

                if let engine {
                    LaneView(
                        engine: engine,
                        participants: recoloured,
                        userID: featured.id,
                        closing: engine.closingProgress
                    )
                    .frame(height: min(max(CGFloat(race.config.participants.count) * 52 + 30, 150), 250))

                    Spacer(minLength: 8)

                    SpectatorGap(engine: engine, featured: featured, field: recoloured)

                    Spacer(minLength: 12)

                    SpectatorStats(engine: engine, featured: featured, unit: app.profile.unit)
                        .padding(.horizontal, 20)
                } else {
                    // The race finished while they were tapping into it. Say so,
                    // and give them somewhere to go.
                    EmptyLine(
                        text: "That race just finished. There are \(app.liveRaces.races.count) more running right now.",
                        actionTitle: "Back to live",
                        action: onClose
                    )
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 90)
            }

            ReactionBurst(reactions: sentReactions)
                .offset(y: -120)
        }
        .atmosphere(.idle)
        .safeAreaInset(edge: .bottom) { controls }
        .statusBarHidden()
    }

    /// Every racer in a spectated race is cool. Nobody here is the user.
    private var recoloured: [Racer] {
        race.config.participants.enumerated().map { i, racer in
            var copy = racer
            copy.isUser = false
            copy.colorIndex = racer.id == featured.id ? 0 : i + 1
            return copy
        }
    }

    // MARK: Marker

    /// Unmistakable. If someone glances at this screen mid-run they must never
    /// think it's their own race.
    private var spectatingMarker: some View {
        // Chalk and aqua, not yellow. The flame below is this screen's one
        // signal element, and two yellows on one screen means neither of them
        // is a signal any more. Aqua also says the right thing here: everything
        // on this screen belongs to someone else.
        HStack(spacing: 10) {
            PulsingDot(color: Track.them)
            Text("SPECTATING")
                .font(Bib.label(14))
                .labelTracking()
                .foregroundStyle(Track.chalk)
            Text("·")
                .foregroundStyle(Track.chalkFaint)
            Text(featured.displayName)
                .font(Bib.label(14))
                .labelTracking()
                .foregroundStyle(Track.them)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(Track.base.opacity(0.6))
                .overlay { Capsule().strokeBorder(Track.them.opacity(0.45), lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spectating \(featured.displayName)")
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            Text(sendCount == 0
                 ? "Tap the flame. They'll feel it."
                 : "Sent \(sendCount) \(sendCount == 1 ? "time" : "times").")
                .font(Prose.caption(15))
                .foregroundStyle(Track.chalkFaint)

            GlassControlBar(spacing: 12) {
                GlassCircleButton(
                    systemImage: "xmark",
                    size: 54,
                    haptic: .back,
                    accessibilityName: "Stop watching"
                ) { onClose() }

                GlassCircleButton(
                    systemImage: "flame.fill",
                    tint: Track.signal,
                    size: 66,
                    haptic: .reaction,
                    accessibilityName: "Send a cheer"
                ) { sendReaction() }
            }
        }
        .padding(.bottom, 10)
    }

    private func sendReaction() {
        let handle = app.profile.handle.isEmpty ? "someone" : app.profile.handle
        let reaction = Reaction(from: handle, at: Date())
        sendCount += 1
        withAnimation(motion.animation(Spring.momentum)) { sentReactions.append(reaction) }
        Task { @MainActor in
            await app.liveRaces.react(to: race.id, from: handle)
            try? await Task.sleep(for: .milliseconds(1800))
            withAnimation(motion.animation(Spring.ui)) {
                sentReactions.removeAll { $0.id == reaction.id }
            }
        }
    }
}

// MARK: - Spectator readouts

/// The gap, from the outside. Same size and shape as the racer's own readout,
/// but coloured for the leader rather than for "you" — because there is no you.
private struct SpectatorGap: View {
    let engine: RaceEngine
    let featured: Racer
    let field: [Racer]

    var body: some View {
        TimelineView(.animation) { _ in
            let gap = engine.displayGap
            let leading = gap >= 0
            VStack(spacing: 2) {
                Text(Fmt.signedMeters(gap))
                    .font(Bib.hero(102))
                    .bibTracking(102)
                    .foregroundStyle(leading ? Track.them : Track.chalk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                HStack(spacing: 7) {
                    Text("METRES")
                        .font(Bib.label(11))
                        .labelTracking()
                        .foregroundStyle(Track.chalkFaint)
                    if let other = engine.headlineGap.flatMap({ h in field.first { $0.id == h.opponent } }) {
                        Text(leading ? "ON \(other.displayName.uppercased())" : "BEHIND \(other.displayName.uppercased())")
                            .font(Bib.label(11))
                            .labelTracking()
                            .foregroundStyle(Track.chalkDim)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SpectatorStats: View {
    let engine: RaceEngine
    let featured: Racer
    let unit: DistanceUnit

    var body: some View {
        TimelineView(.animation) { _ in
            HStack(spacing: 0) {
                stat("PACE", Fmt.pace(engine.displayPace, unit: unit), "/\(unit.short)")
                divider
                stat("DISTANCE", Fmt.distance(engine.userState.distance, unit: unit), unit.short)
                divider
                stat("ELAPSED", Fmt.clock(engine.elapsed), nil)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Track.hairline).frame(width: 1, height: 26)
    }

    private func stat(_ label: String, _ value: String, _ suffix: String?) -> some View {
        VStack(spacing: 3) {
            TrackLabel(label, size: 10)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Bib.numeral(28))
                    .bibTracking(28)
                    .foregroundStyle(Track.chalk)
                if let suffix {
                    Text(suffix).font(Bib.label(11)).foregroundStyle(Track.chalkFaint)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
