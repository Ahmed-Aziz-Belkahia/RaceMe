import SwiftUI

/// After the line.
///
/// The job of this screen is different depending on which way the race went, and
/// it does both at once:
///
/// - **If they won**, give them an artifact worth screenshotting.
/// - **If they lost**, give them a reason to still be here. That's the delta
///   against their own baseline — you can lose a race and still have run the
///   best 5K of your month, and this screen has to say so plainly.
///
/// Either way it ends on **rematch**, prominent. Losing should feel like an
/// unfinished sentence.
struct PostRaceView: View {
    let result: RaceResult
    let profile: RunnerProfile
    var onRematch: () -> Void
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @State private var develop: Double = 0
    @State private var splitsShown = false
    @State private var shareItem: ShareItem?

    @MainActor private var film: PhotoFinishFilm { PhotoFinishFilm.build(from: result) }

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    headline
                    photoFinish
                    baselineDelta
                    splits
                    fieldSummary
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
        }
        .atmosphere(result.userWon ? .won : .lost)
        .safeAreaInset(edge: .bottom) { actions }
        .task { runDevelop() }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image, ChallengeLink.shareText(item.challenge)] + [item.url].compactMap { $0 })
                .presentationBackground(Track.base)
        }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TrackLabel(Fmt.raceName(result.config.distanceMeters))
                TrackLabel(result.config.mode.shortLabel)
                if result.config.scoring == .fair {
                    TrackLabel("Fair", color: Track.chalkFaint)
                }
            }

            Text(headlineText)
                .font(Bib.hero(result.isPersonalRecord ? 76 : 88))
                .bibTracking(88)
                .foregroundStyle(headlineColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subheadText)
                .font(Body.copy(19))
                .foregroundStyle(Track.chalkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .staggeredAppear(0, distance: 18)
    }

    private var headlineText: String {
        if result.isPersonalRecord { return "PERSONAL BEST" }
        return result.userWon ? "WON" : "LOST"
    }

    private var headlineColor: Color {
        // Signal yellow appears exactly once on this screen, and only for a
        // record. If it's showing here, it isn't showing anywhere else.
        if result.isPersonalRecord { return Track.signal }
        return result.userWon ? Track.you : Track.them
    }

    private var subheadText: String {
        guard let opponent = result.config.participants.first(where: { !$0.isUser }) else {
            return "\(Fmt.clock(result.userTime)) — \(Fmt.pace(result.userPace, unit: profile.unit))/\(profile.unit.short.lowercased())."
        }
        let margin = abs(result.margin)
        let m = margin < 1 ? "less than a second" : Fmt.clock(margin)
        return result.userWon
            ? "\(Fmt.clock(result.userTime)). You beat \(opponent.displayName) by \(m)."
            : "\(Fmt.clock(result.userTime)). \(opponent.displayName) by \(m)."
    }

    // MARK: Photo finish

    @MainActor private var photoFinish: some View {
        VStack(alignment: .leading, spacing: 9) {
            TrackLabel("Photo finish")
            PhotoFinishView(film: film, develop: develop, showsChrome: true)
                .frame(height: CGFloat(max(film.lanes.count, 2)) * 34 + 26)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let margin = film.winningMargin {
                Text(margin < 0.5
                     ? "Decided by \(String(format: "%.2f", margin))s at the line."
                     : "\(String(format: "%.2f", margin))s between first and second.")
                    .font(Body.caption(15))
                    .foregroundStyle(Track.chalkFaint)
            }
        }
        .staggeredAppear(1, distance: 18)
    }

    private func runDevelop() {
        guard !motion.reduced else { develop = 1; splitsShown = true; return }
        // The print comes up left to right, and the splits follow it in. Slightly
        // over the 400ms rule on purpose — this is the celebration beat, and it's
        // the only place in the app that's allowed the extra time.
        withAnimation(.spring(duration: 0.9, bounce: 0)) { develop = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(Spring.momentum) { splitsShown = true }
        }
    }

    // MARK: Baseline

    /// The screen's most important twenty points of height when they lost.
    private var baselineDelta: some View {
        let delta = result.deltaToBaseline
        let faster = delta < 0
        return TrackSurface {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    TrackLabel("Against your own form")
                    Text(faster
                         ? "\(Fmt.signedClock(delta)) on your recent average."
                         : "\(Fmt.signedClock(delta)) off your recent average.")
                        .font(Body.headline(18))
                        .foregroundStyle(Track.chalk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(faster
                         ? "That's the number that moves your handicap."
                         : "Your handicap holds. The board doesn't care about one race.")
                        .font(Body.caption(15))
                        .foregroundStyle(Track.chalkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(Fmt.signedClock(delta))
                    .font(Bib.numeral(34))
                    .bibTracking(34)
                    .foregroundStyle(faster ? Track.you : Track.chalkDim)
            }
            .padding(18)
        }
        .staggeredAppear(2, distance: 18)
    }

    // MARK: Splits

    private var splits: some View {
        let userSplits = result.splits[result.userID] ?? []
        let opponentID = result.config.participants.first { !$0.isUser }?.id
        let opponentSplits = opponentID.flatMap { result.splits[$0] } ?? []
        let slowest = (userSplits + opponentSplits).map(\.paceSecPerKm).max() ?? 1
        let fastest = (userSplits + opponentSplits).map(\.paceSecPerKm).min() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            TrackLabel("Split by split")

            if userSplits.isEmpty {
                EmptyLine(
                    text: "Too short for splits. Race a 5K and you'll get a full breakdown.",
                    actionTitle: nil, action: nil
                )
            } else {
                ForEach(Array(userSplits.enumerated()), id: \.element.id) { index, split in
                    SplitRow(
                        index: split.index,
                        unit: profile.unit,
                        userPace: split.paceSecPerKm,
                        opponentPace: opponentSplits.first { $0.index == split.index }?.paceSecPerKm,
                        fastest: fastest,
                        slowest: slowest,
                        shown: splitsShown,
                        order: index
                    )
                }
            }
        }
        .staggeredAppear(3, distance: 18)
    }

    // MARK: Field

    private var fieldSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrackLabel("Finish order")
            ForEach(Array(result.order.enumerated()), id: \.element) { place, id in
                if let racer = result.config.participants.first(where: { $0.id == id }) {
                    HStack(spacing: 12) {
                        Text("\(place + 1)")
                            .font(Bib.numeral(20))
                            .foregroundStyle(Track.chalkFaint)
                            .frame(width: 22, alignment: .leading)
                        AvatarView(mark: racer.mark, color: racer.color, size: 28)
                        Text(racer.isUser ? "You" : racer.displayName)
                            .font(Body.copy(17))
                            .foregroundStyle(racer.isUser ? Track.chalk : Track.chalkDim)
                        Spacer()
                        Text(Fmt.clock(result.times[id] ?? 0))
                            .font(Bib.mono(17, weight: .bold))
                            .foregroundStyle(racer.isUser ? Track.you : Track.chalkDim)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .staggeredAppear(4, distance: 18)
    }

    // MARK: Actions

    /// Rematch is the loud one. Share and dismiss sit beside it.
    ///
    /// All three live in one `GlassEffectContainer` so they merge and refract as
    /// a single piece of material. Left as three separate surfaces they read as
    /// three panes stuck to the screen — which is exactly the three-glass-objects
    /// problem, and exactly what the grouping behaviour exists to solve.
    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassAction(title: "Rematch", systemImage: "arrow.trianglehead.2.clockwise", morphID: GlassID.primaryAction) {
                    onRematch()
                }
                GlassCircleButton(
                    systemImage: "square.and.arrow.up",
                    size: 58,
                    haptic: .commit,
                    accessibilityName: "Share this finish"
                ) {
                    share()
                }
                GlassCircleButton(
                    systemImage: "checkmark",
                    size: 58,
                    haptic: .select,
                    accessibilityName: "Done"
                ) {
                    onDone()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    @MainActor private func share() {
        let challenge = ChallengeLink.from(result: result, sender: profile)
        guard let image = ShareCardRenderer.render(result: result, profile: profile) else { return }
        shareItem = ShareItem(
            image: image,
            challenge: challenge,
            url: ChallengeLink.encode(challenge)
        )
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let challenge: Challenge
    let url: URL?
}

// MARK: - Split row

/// Two bars per kilometre, yours warm and theirs cool, scaled against the
/// fastest and slowest split of the race so the shape of the race is visible at
/// a glance — who went out hard, who had something left.
private struct SplitRow: View {
    let index: Int
    let unit: DistanceUnit
    let userPace: Double
    let opponentPace: Double?
    let fastest: Double
    let slowest: Double
    let shown: Bool
    let order: Int

    @Environment(\.motion) private var motion

    /// Faster = longer bar. Inverted, because a lower pace number is a better
    /// split and a bar that gets shorter when you speed up reads backwards.
    private func width(_ pace: Double) -> Double {
        let span = max(slowest - fastest, 1)
        return 0.22 + 0.78 * (1 - (pace - fastest) / span)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(Bib.numeral(17))
                .foregroundStyle(Track.chalkFaint)
                .frame(width: 20, alignment: .leading)

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 4) {
                    bar(width: geo.size.width * width(userPace), color: Track.you)
                    if let opponentPace {
                        bar(width: geo.size.width * width(opponentPace), color: Track.them)
                    }
                }
            }
            .frame(height: opponentPace == nil ? 12 : 28)

            Text(Fmt.pace(userPace, unit: unit))
                .font(Bib.mono(15, weight: .bold))
                .foregroundStyle(Track.chalk)
                .frame(width: 46, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kilometre \(index), \(Fmt.pace(userPace, unit: unit)) per \(unit.short)")
    }

    private func bar(width: Double, color: Color) -> some View {
        Capsule()
            .fill(color.opacity(0.9))
            .frame(width: shown ? max(width, 6) : 0, height: 12, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(
                motion.animation(Spring.momentum).delay(motion.reduced ? 0 : Double(min(order, 6)) * 0.05),
                value: shown
            )
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Empty state

/// Every empty state gets a line of copy and a way out. An empty screen is an
/// invitation to act, not a dead end.
struct EmptyLine: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(Body.copy(17))
                .foregroundStyle(Track.chalkDim)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle) {
                    Haptics.shared.play(.select)
                    action()
                }
                .font(Bib.label(15))
                .foregroundStyle(Track.you)
                .buttonStyle(.pressable(scale: 0.97, haptic: nil))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Track.elevated.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Track.hairline, lineWidth: 1)
                }
        }
    }
}
