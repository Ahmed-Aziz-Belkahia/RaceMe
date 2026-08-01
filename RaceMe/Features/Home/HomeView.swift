import SwiftUI

/// Home.
///
/// Never empty, never a feed. One staged race with a real opponent and one
/// action, then proof that other people are out there right now, then where you
/// stand, then what you've already done.
///
/// The hero card is solid, not glass — it's dense, it's content, and it lives
/// *under* the floating layer. The only glass on this screen is the tab bar and
/// the primary action, which is two, which is the ceiling.
struct HomeView: View {
    @Bindable var app: AppState

    @Environment(\.motion) private var motion

    private var profile: RunnerProfile { app.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                greeting
                heroCard
                liveNow
                boardPreview
                recentFinishes
                Color.clear.frame(height: 90)
            }
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .atmosphere(.idle)
        .refreshable { await app.refresh() }
    }

    // MARK: Greeting

    /// Uses their answers by name. If they told us about a rival, the rival is
    /// here — that's one of at least three places the name shows up after
    /// onboarding.
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            TrackLabel(dayLabel)
            Text(line)
                .font(Body.title(28))
                .foregroundStyle(Track.chalk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .staggeredAppear(0)
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private var line: String {
        if let rival = profile.rivalMention, profile.totalRaces < 6 {
            let races = max(1, 4 - profile.totalRaces)
            return "You're \(races) \(races == 1 ? "race" : "races") from beating \(rival)'s pace."
        }
        switch profile.selfImage.voice {
        case .cocky:
            return profile.careerWins > profile.careerLosses
                ? "You're \(profile.record). Keep it that way."
                : "You're \(profile.record). That needs fixing."
        case .direct:
            return "\(profile.frequency.perWeek) races this week. Here's the first."
        case .encouraging:
            return "Someone's out there at your pace right now."
        }
    }

    // MARK: Hero

    /// One staged race, chosen from their onboarding answers, with an honest
    /// projection and one action.
    @ViewBuilder
    private var heroCard: some View {
        if let staged = app.stagedRace {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            TrackLabel(Fmt.raceName(staged.config.distanceMeters), color: Track.chalkDim)
                            TrackLabel(staged.config.mode.shortLabel, color: Track.chalkFaint)
                            if staged.config.scoring == .fair {
                                TrackLabel("Fair", color: Track.chalkFaint)
                            }
                        }
                        Text(opponentTitle(staged))
                            .font(Body.title(26))
                            .foregroundStyle(Track.chalk)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    if let opponent = staged.config.opponents.first {
                        AvatarView(mark: opponent.mark, color: opponent.color, size: 46)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                Text(staged.rationale)
                    .font(Body.copy(16))
                    .foregroundStyle(Track.chalkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                // A live mini-lane, so the card is already showing the thing the
                // button will start.
                MiniLane(runners: previewRunners(staged))
                    .frame(height: 54)
                    .padding(.horizontal, 14)
                    .padding(.top, 16)

                HStack(spacing: 8) {
                    Circle()
                        .fill(staged.projectedOutcome.accent)
                        .frame(width: 6, height: 6)
                    Text(staged.projectedOutcome.headline)
                        .font(Body.caption(15))
                        .foregroundStyle(Track.chalkDim)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                GlassAction(title: "Race now", systemImage: "figure.run", morphID: GlassID.primaryAction) {
                    app.startStagedRace()
                }
                .padding(18)
            }
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Track.elevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Track.hairline, lineWidth: 1)
                    }
            }
            .padding(.horizontal, 20)
            .staggeredAppear(1)
        } else {
            EmptyLine(
                text: "Nothing staged yet. Pull to refresh, or race your own ghost — it's the same loop and you'll have a time to defend.",
                actionTitle: "Race my ghost",
                action: { app.startGhostRace() }
            )
            .padding(.horizontal, 20)
        }
    }

    private func opponentTitle(_ staged: StagedRace) -> String {
        guard let opponent = staged.config.opponents.first else { return "Solo effort" }
        return staged.config.mode == .group
            ? "You and \(staged.config.opponents.count) others"
            : "You vs \(opponent.displayName)"
    }

    private func previewRunners(_ staged: StagedRace) -> [MiniLane.Runner] {
        staged.config.participants.enumerated().map { i, racer in
            MiniLane.Runner(
                id: racer.id, color: racer.color, progress: 0.06,
                gapToLeader: i == 0 ? 0 : -2, isUser: racer.isUser
            )
        }
    }

    // MARK: Live now

    /// Social proof, and it's never empty — the director keeps eight races
    /// running at all times, because a strip with nothing in it tells a new user
    /// that nobody uses this.
    private var liveNow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // Cool, not warm. These are other people's races. Rust means
                // "you" everywhere else in the app, and a warm dot over a strip
                // of strangers quietly breaks the one rule the product rests on.
                PulsingDot(color: Track.them)
                TrackLabel("Live now", color: Track.chalkDim)
                Spacer()
                Text("\(app.liveRaces.races.count)")
                    .font(Bib.mono(13, weight: .bold))
                    .foregroundStyle(Track.chalkFaint)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(app.liveRaces.races) { race in
                        LiveRaceCard(race: race, director: app.liveRaces) {
                            Haptics.shared.play(.commit)
                            app.spectating = race
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .staggeredAppear(2)
    }

    // MARK: Board

    private var boardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TrackLabel("This week", color: Track.chalkDim)
                Spacer()
                Button("Full board") {
                    Haptics.shared.play(.select)
                    withAnimation(motion.animation(Spring.snap)) { app.tab = .board }
                }
                .font(Bib.label(12))
                .foregroundStyle(Track.you)
                .buttonStyle(.pressable(scale: 0.97, haptic: nil))
            }
            .padding(.horizontal, 20)

            if let league = app.league {
                VStack(spacing: 0) {
                    // A three-row window around the user, which is the only part
                    // of a twenty-runner bracket that matters on a home screen.
                    ForEach(windowAroundUser(league.entries), id: \.id) { entry in
                        LeaderboardRow(entry: entry, zone: league.zone(for: entry.rank), compact: true)
                    }
                }
                .padding(.horizontal, 20)

                Text(league.urgencyLine())
                    .font(Body.caption(15))
                    .foregroundStyle(Track.chalkDim)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            } else {
                EmptyLine(
                    text: LeaderboardScope.league.emptyLine,
                    actionTitle: LeaderboardScope.league.emptyAction,
                    action: { app.startStagedRace() }
                )
                .padding(.horizontal, 20)
            }
        }
        .staggeredAppear(3)
    }

    private func windowAroundUser(_ entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        guard let index = entries.firstIndex(where: \.isUser) else { return Array(entries.prefix(3)) }
        let lower = max(0, index - 1)
        let upper = min(entries.count, lower + 3)
        return Array(entries[lower..<upper])
    }

    // MARK: Recent

    private var recentFinishes: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackLabel("Recent finishes", color: Track.chalkDim)
                .padding(.horizontal, 20)

            if app.recentResults.isEmpty {
                EmptyLine(
                    text: "No finishes yet. The first one takes about twenty minutes and you'll have something to defend after it.",
                    actionTitle: "Start the staged race",
                    action: { app.startStagedRace() }
                )
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(app.recentResults.prefix(4)) { result in
                        RecentFinishRow(result: result) {
                            Haptics.shared.play(.select)
                            app.postRace = result
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .staggeredAppear(4)
    }
}

// MARK: - Live race card

/// Reads its own race's engine at draw time, at a rate suited to a 44-point
/// lane. Eight of these on screen at once, so it deliberately doesn't ask for
/// display-rate frames — those belong to whatever race the user is actually in.
private struct LiveRaceCard: View {
    let race: LiveRace
    let director: LiveRacesDirector
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Text(race.config.user.displayName)
                        .font(Body.caption(15))
                        .foregroundStyle(Track.chalk)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(Track.chalkFaint)
                    Text(Fmt.raceName(race.config.distanceMeters))
                        .font(Bib.label(11))
                        .labelTracking()
                        .foregroundStyle(Track.chalkDim)
                    Spacer(minLength: 0)
                }

                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { _ in
                    let engine = director.engine(for: race.id)
                    VStack(spacing: 10) {
                        MiniLane(runners: engine.map { MiniLane.runners(from: $0) }
                                 ?? MiniLane.runners(from: race))
                            .frame(height: 44)

                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Track.chalkFaint)
                            Text("\(race.spectators)")
                                .font(Bib.mono(12, weight: .bold))
                                .foregroundStyle(Track.chalkFaint)
                            Spacer()
                            Text("\(Int(progress(engine) * 100))%")
                                .font(Bib.mono(12, weight: .bold))
                                .foregroundStyle(Track.chalkFaint)
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 216)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Track.elevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Track.hairline, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.pressable(scale: 0.97, haptic: nil))
        .accessibilityLabel("Watch \(race.config.user.displayName) race \(Fmt.raceName(race.config.distanceMeters)), \(race.spectators) watching")
    }

    private func progress(_ engine: RaceEngine?) -> Double {
        guard let engine else { return race.snapshot.progress }
        let lead = engine.config.participants.map { engine.state($0.id).distance }.max() ?? 0
        return min(lead / engine.distanceMeters, 1)
    }
}

/// The live indicator. A slow pulse, not a blink — a blinking dot reads as an
/// error light.
struct PulsingDot: View {
    var color: Color = Track.you
    @Environment(\.motion) private var motion
    @State private var start = Date()

    var body: some View {
        Group {
            if motion.reduced {
                Circle().fill(color).frame(width: 7, height: 7)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    let p = (sin(t * 2.1) + 1) / 2
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.25 * (1 - p)))
                            .frame(width: 7 + 11 * p, height: 7 + 11 * p)
                        Circle().fill(color).frame(width: 7, height: 7)
                    }
                    .frame(width: 18, height: 18)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Recent finish row

/// Each one uses its photo-finish strip as the thumbnail. That's what makes a
/// history list feel like a shelf of prints rather than a table of times.
private struct RecentFinishRow: View {
    let result: RaceResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                PhotoFinishView(
                    film: PhotoFinishFilm.build(from: result),
                    develop: 1, showsChrome: false, columns: 120
                )
                .frame(width: 72, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Body.copy(16))
                        .foregroundStyle(Track.chalk)
                        .lineLimit(1)
                    Text("\(Fmt.raceName(result.config.distanceMeters)) · \(Fmt.clock(result.userTime))")
                        .font(Bib.mono(13, weight: .medium))
                        .foregroundStyle(Track.chalkFaint)
                }

                Spacer(minLength: 0)

                Text(result.userWon ? "W" : "L")
                    .font(Bib.numeral(22))
                    .foregroundStyle(result.userWon ? Track.you : Track.them)
                    .frame(width: 22)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Track.elevated.opacity(0.7))
            }
        }
        .buttonStyle(.pressable(scale: 0.985, haptic: nil))
        .accessibilityLabel("\(title), \(Fmt.clock(result.userTime)), \(result.userWon ? "won" : "lost")")
    }

    private var title: String {
        if result.isPersonalRecord { return "Personal best" }
        guard let opponent = result.config.opponents.first else { return "Solo" }
        return result.userWon ? "Beat \(opponent.displayName)" : "\(opponent.displayName) got you"
    }
}
