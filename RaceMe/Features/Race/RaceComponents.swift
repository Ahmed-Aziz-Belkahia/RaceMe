import SwiftUI

// MARK: - The gap

/// The single biggest thing on the screen.
///
/// Sign and colour carry all of the meaning. `+12` in rust means you're up;
/// `−8` in aqua means you're not. Someone reads this at arm's length, in
/// daylight, while moving, breathing hard — so there is no sentence to parse,
/// no icon to decode, and no legend. Two facts: how much, and which way.
struct GapReadout: View {
    let engine: RaceEngine
    let opponent: Racer?
    let scoring: Scoring
    let closing: Double

    @Environment(\.motion) private var motion

    /// One face, one frame, always. An earlier version scaled the type down as
    /// the gap grew past 9 and past 99 — which meant the single most important
    /// number on the screen physically resized itself twice during a close race,
    /// right at the moment the reader needs it to hold still. Now the size is
    /// fixed and `minimumScaleFactor` absorbs the rare four-digit case.
    private let face: CGFloat = 112

    var body: some View {
        TimelineView(.animation) { _ in
            let gap = engine.displayGap
            let ahead = gap >= 0
            let color = ahead ? Track.you : Track.them

            VStack(spacing: 2) {
                Text(Fmt.signedMeters(gap))
                    .font(Bib.hero(face))
                    .bibTracking(face)
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.28 + 0.3 * closing), radius: 26 + 22 * closing, y: 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    // No `contentTransition` here on purpose. The value already
                    // arrives pre-interpolated from the engine and re-renders
                    // every display frame — a numeric-text transition would be
                    // animating an animation, and it needs a `withAnimation`
                    // wrapper that a TimelineView body doesn't have anyway.
                    .frame(height: face * 0.78, alignment: .center)

                HStack(spacing: 7) {
                    Text("METRES")
                        .font(Bib.label(13))
                        .labelTracking()
                        .foregroundStyle(Track.chalkFaint)
                    if let opponent {
                        Text(ahead ? "ON \(opponent.displayName.uppercased())" : "BEHIND \(opponent.displayName.uppercased())")
                            .font(Bib.label(13))
                            .labelTracking()
                            .foregroundStyle(color.opacity(0.85))
                    }
                    if scoring == .fair {
                        Text("FAIR")
                            .font(Bib.label(12))
                            .labelTracking()
                            .foregroundStyle(Track.chalkFaint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay {
                                Capsule().strokeBorder(Track.chalkFaint.opacity(0.5), lineWidth: 1)
                            }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gap")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let m = Int(abs(engine.displayGap).rounded())
        guard let opponent else { return "\(m) metres" }
        return engine.displayGap >= 0
            ? "\(m) metres ahead of \(opponent.displayName)"
            : "\(m) metres behind \(opponent.displayName)"
    }
}

// MARK: - Your own numbers

/// Pace, distance, and what's left. Stable and glanceable — these are the
/// numbers you check when you're not checking the gap, and they must never move
/// around underneath you.
///
/// Elapsed lives in the header pill and only there. Two clocks on one screen is
/// one clock too many when the reader is breathing hard.
struct RaceStatRow: View {
    let engine: RaceEngine
    let unit: DistanceUnit

    var body: some View {
        TimelineView(.animation) { _ in
            HStack(spacing: 0) {
                stat(
                    label: "PACE",
                    value: Fmt.pace(engine.displayPace, unit: unit),
                    suffix: "/\(unit.short)"
                )
                divider
                stat(
                    label: "DISTANCE",
                    value: Fmt.distance(engine.userState.distance, unit: unit),
                    suffix: unit.short
                )
                divider
                stat(
                    label: "TO GO",
                    value: Fmt.distance(engine.remainingMeters, unit: unit),
                    suffix: unit.short
                )
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Track.hairline)
            .frame(width: 1, height: 26)
    }

    /// Everything on this row is sized for arm's length in daylight. The caps
    /// labels sit at 12 rather than the 17 the rule sets for body copy — they're
    /// four-character words at high contrast that a runner learns once and then
    /// never reads again, and pushing them to 17 would crowd the numbers, which
    /// are the part that actually has to be legible mid-stride.
    private func stat(label: String, value: String, suffix: String?) -> some View {
        VStack(spacing: 3) {
            TrackLabel(label, size: 12)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Bib.numeral(32))
                    .bibTracking(32)
                    .foregroundStyle(Track.chalk)
                if let suffix {
                    Text(suffix)
                        .font(Bib.label(12))
                        .foregroundStyle(Track.chalkFaint)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Opponent strip

/// Small cards that physically reorder as positions change.
///
/// They travel — a racer moving from third to second slides past the card it
/// overtook, the same way it just happened on the lane. Cross-fading them would
/// throw away the only moment in the race where the standings are legible as an
/// event rather than a state.
struct OpponentStrip: View {
    let engine: RaceEngine
    let opponents: [Racer]
    let standings: [UUID]
    let scoring: Scoring

    @Namespace private var strip
    @Environment(\.motion) private var motion

    private var ordered: [Racer] {
        standings.compactMap { id in opponents.first { $0.id == id } }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(ordered) { opponent in
                    OpponentCard(engine: engine, racer: opponent)
                        // Matched geometry alone. An explicit `.id()` on top
                        // fights it — SwiftUI treats the row as a new view and
                        // the card pops instead of travelling.
                        .matchedGeometryEffect(id: opponent.id, in: strip)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .animation(motion.animation(Spring.reorder), value: standings)
    }
}

private struct OpponentCard: View {
    let engine: RaceEngine
    let racer: Racer

    var body: some View {
        TimelineView(.animation) { _ in
            let state = engine.state(racer.id)
            let gap = engine.gap(to: racer.id)
            let ahead = gap >= 0

            HStack(spacing: 9) {
                AvatarView(mark: racer.mark, color: racer.color, size: 30, emphasized: state.place == 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(racer.displayName)
                        .font(Prose.copy(17))
                        .foregroundStyle(Track.chalk)
                        .lineLimit(1)
                    Text(Fmt.pace(state.pace) + "/km")
                        .font(Bib.mono(15, weight: .medium))
                        .foregroundStyle(Track.chalkFaint)
                }

                Text(Fmt.signedMeters(-gap))
                    .font(Bib.numeral(23))
                    .bibTracking(23)
                    .foregroundStyle(ahead ? Track.chalkDim : racer.color)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Track.elevated.opacity(0.9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                state.place == 1 ? racer.color.opacity(0.55) : Track.hairline,
                                lineWidth: 1
                            )
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Commentary

/// One line, rolling. Events push up from below and leave through the top, so
/// the ticker reads as a strip of film moving past rather than text being
/// replaced in place.
struct CommentaryTicker: View {
    let events: [RaceEvent]
    @Environment(\.motion) private var motion

    private var latest: RaceEvent? { events.last }

    var body: some View {
        ZStack {
            if let latest {
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(latest.accent.color)
                        .frame(width: 2, height: 15)
                    Text(latest.text)
                        .font(Prose.copy(17))
                        .foregroundStyle(latest.accent == .neutral ? Track.chalkDim : latest.accent.color)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .id(latest.id)
                .transition(
                    motion.reduced
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                )
            }
        }
        .frame(height: 24, alignment: .leading)
        .clipped()
        .animation(motion.animation(Spring.ui), value: latest?.id)
        .accessibilityLabel("Commentary")
        .accessibilityValue(latest?.text ?? "")
    }
}

// MARK: - Countdown

/// The ritual.
///
/// Chalk numerals scale *down* through the frame — arriving huge and settling —
/// while the haptics get sharper each tick. Ten seconds of anticipation before
/// a race is worth more than most features, and it costs one view.
struct CountdownOverlay: View {
    let value: Int
    @Environment(\.motion) private var motion
    @State private var scale: CGFloat = 3.4
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            // A chalk ring, drawn like it was scuffed onto the track.
            Circle()
                .strokeBorder(Track.chalk.opacity(0.10), lineWidth: 2)
                .frame(width: 260, height: 260)
                .scaleEffect(motion.reduced ? 1 : scale * 0.42 + 0.6)

            Text("\(value)")
                .font(Bib.chalk(210))
                .tracking(-10)
                .foregroundStyle(Track.chalk)
                .scaleEffect(motion.reduced ? 1 : scale)
                .opacity(opacity)
                .shadow(color: Track.you.opacity(0.35), radius: 40)
        }
        .onAppear { animateIn() }
        .onChange(of: value) { _, _ in
            scale = 3.4
            opacity = 0
            animateIn()
        }
        .accessibilityLabel("Starting in \(value)")
    }

    private func animateIn() {
        withAnimation(motion.animation(.spring(duration: 0.38, bounce: 0.14))) {
            scale = 1
            opacity = 1
        }
    }
}

/// GO. One frame of chalk, one sharp transient, then it's gone.
struct GoFlash: View {
    @Environment(\.motion) private var motion
    @State private var shown = false

    var body: some View {
        Text("GO")
            .font(Bib.chalk(150))
            .tracking(-6)
            .foregroundStyle(Track.you)
            .scaleEffect(motion.reduced ? 1 : (shown ? 1.35 : 0.85))
            .opacity(shown ? 0 : 1)
            .shadow(color: Track.you.opacity(0.6), radius: 50)
            .onAppear {
                withAnimation(motion.animation(.spring(duration: 0.34, bounce: 0.3))) { shown = true }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Spectator reactions

/// A 🔥 arriving mid-race. The one deliberate emoji in the interface — it's a
/// gesture someone sent you, not an icon we chose.
struct ReactionBurst: View {
    let reactions: [Reaction]
    @Environment(\.motion) private var motion

    var body: some View {
        ZStack {
            ForEach(reactions) { reaction in
                VStack(spacing: 4) {
                    Text("🔥").font(.system(size: 30))
                    Text(reaction.from)
                        .font(Bib.label(11))
                        .labelTracking()
                        .foregroundStyle(Track.signal)
                }
                .transition(
                    motion.reduced
                        ? .opacity
                        : .asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal: .offset(y: -40).combined(with: .opacity)
                        )
                )
                .id(reaction.id)
            }
        }
        .animation(motion.animation(Spring.momentum), value: reactions.map(\.id))
        .allowsHitTesting(false)
        .accessibilityLabel(reactions.isEmpty ? "" : "\(reactions.count) people cheering")
    }
}

// MARK: - Fault banner

/// What happened, and what to do. No apology, nothing vague.
struct FaultBanner: View {
    let fault: MovementFault

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Track.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text(fault.headline)
                    .font(Prose.caption(15))
                    .foregroundStyle(Track.chalk)
                Text(fault.recovery)
                    .font(Prose.caption(14))
                    .foregroundStyle(Track.chalkDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Track.elevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Track.signal.opacity(0.3), lineWidth: 1)
                }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
