import SwiftUI

/// The Racer Card.
///
/// The payoff of onboarding, the top of the profile, and the thing the paywall
/// puts at stake. It's a bib and a spec sheet at once: their archetype, derived
/// from answers they actually gave; their current 5K against a projection eight
/// weeks out; their handicap; and three traits charted.
///
/// It's the one glass object allowed to carry data, because it *is* the object —
/// a floating hero, never with another glass surface beside it, and never
/// covering a list.
struct RacerCardView: View {
    let profile: RunnerProfile
    /// Runs the light sweep once. Off in the profile, on for the reveal.
    var sweep: Bool = false
    var compact: Bool = false
    /// Renders on a solid surface instead of glass.
    ///
    /// Used wherever the screen's glass budget is already spent — the paywall
    /// puts its glass on the plans, so the card goes solid there. Two glass
    /// surfaces is the ceiling, and the card loses that argument to the thing
    /// the user has to tap.
    var plain: Bool = false

    @Environment(\.motion) private var motion
    @Environment(\.glassNamespace) private var glassNS
    @State private var sweepPhase: CGFloat = -1

    private var traits: [Trait] { profile.traits }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: compact ? 14 : 22)
            archetype
            Spacer(minLength: compact ? 14 : 22)
            projection
            Spacer(minLength: compact ? 14 : 20)
            traitChart
        }
        .padding(compact ? 18 : 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface(plain: plain, namespace: glassNS))
        .overlay { sweepLayer }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onAppear {
            guard sweep, !motion.reduced else { return }
            withAnimation(.spring(duration: 1.15, bounce: 0).delay(0.35)) { sweepPhase = 2 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your racer card")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                TrackLabel("Racer card", size: 10)
                HStack(spacing: 9) {
                    AvatarView(mark: profile.mark, color: Track.you, size: 30)
                    Text(profile.handle.isEmpty ? "you" : profile.handle)
                        .font(Body.headline(19))
                        .foregroundStyle(Track.chalk)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                TrackLabel("Record", size: 10)
                Text(profile.record)
                    .font(Bib.numeral(24))
                    .bibTracking(24)
                    .foregroundStyle(Track.chalk)
            }
        }
    }

    // MARK: Archetype

    private var archetype: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(profile.archetype.name.uppercased())
                .font(Bib.numeral(compact ? 38 : 46))
                .bibTracking(compact ? 38 : 46)
                .foregroundStyle(Track.you)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !compact {
                Text(profile.archetype.blurb)
                    .font(Body.copy(17))
                    .foregroundStyle(Track.chalkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Projection

    /// Now, and where eight weeks of racing puts you. The projection is
    /// deliberately modest — a promise the app can't keep costs far more in week
    /// nine than it wins in week one.
    private var projection: some View {
        HStack(alignment: .bottom, spacing: 0) {
            stat(
                label: "5K now",
                value: Fmt.clock(profile.current5KSeconds),
                color: Track.chalk
            )

            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Track.chalkFaint)
                Text("8 WKS")
                    .font(Bib.label(9))
                    .labelTracking()
                    .foregroundStyle(Track.chalkFaint)
            }
            .frame(width: 54)
            .padding(.bottom, 6)

            stat(
                label: "Projected",
                value: Fmt.clock(profile.projected5KSeconds),
                color: Track.signal
            )

            Spacer(minLength: 0)

            stat(
                label: "Handicap",
                value: Fmt.pace(profile.handicapPaceSecPerKm, unit: profile.unit),
                suffix: "/\(profile.unit.short.lowercased())",
                color: Track.chalk,
                alignment: .trailing
            )
        }
    }

    private func stat(
        label: String, value: String, suffix: String? = nil,
        color: Color, alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            TrackLabel(label, size: 10)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Bib.numeral(compact ? 24 : 28))
                    .bibTracking(28)
                    .foregroundStyle(color)
                if let suffix {
                    Text(suffix)
                        .font(Bib.label(10))
                        .foregroundStyle(Track.chalkFaint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Traits

    /// Three lanes. Charted in the same visual language as the race itself
    /// rather than as a generic bar chart — chalk rules, rust fill, lane ticks.
    private var traitChart: some View {
        VStack(alignment: .leading, spacing: 9) {
            TrackLabel("Traits", size: 10)
            ForEach(traits) { trait in
                TraitLane(trait: trait, animates: sweep)
            }
        }
    }

    // MARK: Sweep

    /// Light travelling across the surface, once. This is what makes it read as
    /// a physical card catching a light rather than a rectangle appearing.
    @ViewBuilder
    private var sweepLayer: some View {
        if sweep && !motion.reduced {
            GeometryReader { geo in
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Track.chalk.opacity(0.16), location: 0.45),
                        .init(color: Track.chalk.opacity(0.30), location: 0.5),
                        .init(color: Track.chalk.opacity(0.16), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * 1.6)
                .offset(x: geo.size.width * sweepPhase - geo.size.width * 0.3)
                .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Glass or solid, and the morph identity travels with the glass version so the
/// card that flipped in during onboarding is the same object that lands at the
/// top of the profile.
private struct CardSurface: ViewModifier {
    let plain: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if plain {
            content.background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Track.elevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Track.hairline, lineWidth: 1)
                    }
            }
        } else {
            content
                .glassEffect(.regular.tint(Track.elevated.opacity(0.55)), in: .rect(cornerRadius: 26))
                .glassEffectID(GlassID.racerCard, in: namespace)
        }
    }
}

private struct TraitLane: View {
    let trait: Trait
    let animates: Bool

    @Environment(\.motion) private var motion
    @State private var filled = false

    var body: some View {
        HStack(spacing: 12) {
            Text(trait.name)
                .font(Body.caption(15))
                .foregroundStyle(Track.chalkDim)
                .frame(width: 86, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Lane ticks behind the fill — the bar sits *in* a lane
                    // rather than floating on nothing.
                    HStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { _ in
                            Rectangle()
                                .fill(Track.chalk.opacity(0.09))
                                .frame(width: 1)
                            Spacer(minLength: 0)
                        }
                    }
                    Capsule()
                        .fill(Track.you)
                        .frame(width: (filled || !animates) ? geo.size.width * trait.value : 0)
                }
            }
            .frame(height: 8)

            Text("\(Int(trait.value * 100))")
                .font(Bib.mono(13, weight: .bold))
                .foregroundStyle(Track.chalkFaint)
                .frame(width: 26, alignment: .trailing)
        }
        .onAppear {
            guard animates, !motion.reduced else { filled = true; return }
            withAnimation(.spring(duration: 0.7, bounce: 0.15).delay(0.5)) { filled = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trait.name), \(Int(trait.value * 100)) out of 100")
    }
}

// MARK: - S11 · The reveal

/// The card arrives by flipping in, with light sweeping across it.
///
/// Everything before this screen was them giving; this is the first thing the
/// app gives back, and it's built entirely out of what they said. "It changes
/// every time you race" is the promise that makes the rest of the product feel
/// like it accumulates.
struct CardRevealScreen: View {
    let profile: RunnerProfile
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @State private var flipped = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("This is your card.")
                    .font(Body.title(32))
                    .foregroundStyle(Track.chalk)
                Text("It changes every time you race.")
                    .font(Body.copy(18))
                    .foregroundStyle(Track.chalkDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .opacity(flipped ? 1 : 0)
            .animation(motion.animation(Spring.ui).delay(0.5), value: flipped)

            Spacer(minLength: 20)

            RacerCardView(profile: profile, sweep: true)
                .padding(.horizontal, 20)
                .rotation3DEffect(
                    .degrees(motion.reduced ? 0 : (flipped ? 0 : -84)),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    perspective: 0.55
                )
                .opacity(flipped || motion.reduced ? 1 : 0)

            Spacer(minLength: 20)

            GlassAction(title: "Good", morphID: nil) {
                onDone()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .opacity(flipped ? 1 : 0)
            .animation(motion.animation(Spring.momentum).delay(0.7), value: flipped)
        }
        .task {
            Haptics.shared.play(.commit)
            withAnimation(motion.animation(.spring(duration: 0.72, bounce: 0.22))) { flipped = true }
        }
    }
}
