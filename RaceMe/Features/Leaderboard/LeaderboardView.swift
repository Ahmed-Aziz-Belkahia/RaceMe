import SwiftUI

/// Friends, Global, League.
///
/// Rows physically reorder rather than re-rendering — when your position
/// changes you should see yourself move past someone, because that's the whole
/// emotional content of a leaderboard. The user's row pins to the top when
/// they've been scrolled past, so "where am I" is never more than a glance.
///
/// The top three are differentiated by weight, lane markings and a rule, not by
/// medal emoji. This app doesn't use emoji as interface.
struct LeaderboardView: View {
    @Bindable var app: AppState

    @Environment(\.motion) private var motion
    @State private var scope: LeaderboardScope = .league
    @State private var entries: [LeaderboardEntry] = []
    @State private var loading = true
    @State private var userRowVisible = true
    @Namespace private var rowSpace

    private var league: League? { app.league }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    scopePicker
                        .padding(.bottom, 14)

                    if scope == .league, let league {
                        LeagueBanner(league: league)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }

                    if loading {
                        LoadingRules()
                            .padding(.horizontal, 20)
                    } else if entries.isEmpty {
                        EmptyLine(
                            text: scope.emptyLine,
                            actionTitle: scope.emptyAction,
                            action: {
                                if scope == .friends { shareInvite() } else { app.startStagedRace() }
                            }
                        )
                        .padding(.horizontal, 20)
                    } else {
                        rows
                    }

                    Color.clear.frame(height: 96)
                }
            }
            .scrollIndicators(.hidden)

            // Pinned row. Appears only once the real one has scrolled away.
            if let user = entries.first(where: \.isUser), !userRowVisible {
                LeaderboardRow(
                    entry: user,
                    zone: league?.zone(for: user.rank) ?? .holding,
                    pinned: true
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .transition(motion.reduced ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(motion.animation(Spring.ui), value: userRowVisible)
        .atmosphere(.idle)
        .task(id: scope) { await load() }
        .refreshable { await load() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Board")
                .font(Prose.title(32))
                .foregroundStyle(Track.chalk)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// Chalk-underlined segments. A system segmented control would be the first
    /// thing on this screen traceable to a template.
    private var scopePicker: some View {
        HStack(spacing: 22) {
            ForEach(LeaderboardScope.allCases) { option in
                Button {
                    guard option != scope else { return }
                    Haptics.shared.play(.select)
                    withAnimation(motion.animation(Spring.snap)) { scope = option }
                } label: {
                    VStack(spacing: 7) {
                        Text(option.title.uppercased())
                            .font(Bib.label(14))
                            .labelTracking()
                            .foregroundStyle(scope == option ? Track.chalk : Track.chalkFaint)
                        Rectangle()
                            .fill(scope == option ? Track.you : .clear)
                            .frame(height: 2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable(scale: 0.97, haptic: nil))
                .accessibilityAddTraits(scope == option ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: Rows

    /// Rows travel rather than re-render.
    ///
    /// A row moving from ninth to seventh has to be seen sliding past the two
    /// it overtook — that motion *is* the content of a leaderboard, and a list
    /// that simply redraws in a new order throws it away. Two things make it
    /// work: matched geometry so each row keeps its identity across the reorder,
    /// and a plain `VStack` for brackets of twenty so every row actually exists
    /// and has somewhere to travel from. Big boards fall back to a lazy stack,
    /// where off-screen travel isn't observable anyway.
    @ViewBuilder
    private var rows: some View {
        if entries.count <= 24 {
            VStack(spacing: 6) { rowContent }
                .padding(.horizontal, 20)
                .animation(motion.animation(Spring.reorder), value: entries)
        } else {
            LazyVStack(spacing: 6) { rowContent }
                .padding(.horizontal, 20)
                .animation(motion.animation(Spring.reorder), value: entries)
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        ForEach(entries) { entry in
            LeaderboardRow(
                entry: entry,
                zone: scope == .league ? (league?.zone(for: entry.rank) ?? .holding) : .holding
            )
            .matchedGeometryEffect(id: entry.id, in: rowSpace)
            .onAppear { if entry.isUser { userRowVisible = true } }
            .onDisappear { if entry.isUser { userRowVisible = false } }

            // Promotion and relegation lines are drawn *on the track*, as chalk,
            // between the rows they separate. They stay put while rows cross
            // them, which is the whole point of drawing them at all.
            if scope == .league, let league {
                if entry.rank == League.promotionCount {
                    ZoneRule(label: "Promotion", tint: Track.you)
                } else if entry.rank == league.entries.count - League.relegationCount {
                    ZoneRule(label: "Relegation", tint: Track.them)
                }
            }
        }
    }

    // MARK: Data

    private func load() async {
        loading = entries.isEmpty
        let user = app.profile.asRacer()
        if scope == .league {
            let value = try? await app.services.leaderboards.league(user: user)
            app.league = value
            entries = value?.entries ?? []
        } else {
            entries = (try? await app.services.leaderboards.board(scope, user: user)) ?? []
        }
        loading = false
    }

    private func shareInvite() {
        // An invite is just a challenge with no time on it yet.
        let challenge = Challenge(
            fromName: app.profile.handle.isEmpty ? "A runner" : app.profile.handle,
            fromHandle: app.profile.handle,
            distanceMeters: RaceStaging.preferredDistance(for: app.profile),
            scoring: .fair,
            mode: .headToHead,
            paceSecPerKm: app.profile.race5KPaceSecPerKm,
            timeSeconds: nil,
            seed: UInt64(abs(UUID().hashValue))
        )
        guard let url = ChallengeLink.encode(challenge) else { return }
        let activity = UIActivityViewController(
            activityItems: [ChallengeLink.shareText(challenge), url], applicationActivities: nil
        )
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?
            .present(activity, animated: true)
    }
}

// MARK: - Row

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    var zone: League.Zone = .holding
    var compact: Bool = false
    var pinned: Bool = false

    @Environment(\.motion) private var motion

    /// The top three get weight and a rule, not a medal. Rank one is chalk-white
    /// and heavier; two and three step down. Nothing here borrows a colour that
    /// belongs to the warm/cool split.
    private var rankColor: Color {
        if entry.isUser { return Track.you }
        switch entry.rank {
        case 1: return Track.chalk
        case 2: return Track.chalk.opacity(0.75)
        case 3: return Track.chalk.opacity(0.55)
        default: return Track.chalkFaint
        }
    }

    private var stripeTint: Color? {
        if zone != .holding { return zone.tint.opacity(0.7) }
        switch entry.rank {
        case 1: return Track.chalk.opacity(0.8)
        case 2: return Track.chalk.opacity(0.42)
        case 3: return Track.chalk.opacity(0.22)
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("\(entry.rank)")
                    .font(Bib.numeral(entry.rank <= 3 ? 24 : 20))
                    .bibTracking(22)
                    .foregroundStyle(rankColor)
                    .frame(minWidth: 26, alignment: .leading)

                if entry.movement != 0 && !compact {
                    Image(systemName: entry.movement > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(entry.movement > 0 ? Track.you.opacity(0.7) : Track.them.opacity(0.6))
                }
            }
            .frame(width: 44, alignment: .leading)

            AvatarView(
                mark: entry.racer.mark,
                color: entry.isUser ? Track.you : Track.opponentNeutral,
                size: compact ? 26 : 32
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isUser ? "You" : entry.racer.displayName)
                    .font(Prose.copy(compact ? 15 : 17))
                    .foregroundStyle(entry.isUser ? Track.chalk : Track.chalkDim)
                    .lineLimit(1)
                if !compact {
                    Text("\(entry.racesThisWeek) \(entry.racesThisWeek == 1 ? "race" : "races")")
                        .font(Prose.caption(13))
                        .foregroundStyle(Track.chalkFaint)
                }
            }

            Spacer(minLength: 0)

            Text("\(entry.points)")
                .font(Bib.numeral(compact ? 19 : 22))
                .bibTracking(22)
                .foregroundStyle(entry.isUser ? Track.you : Track.chalkDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 9 : 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(entry.isUser ? Track.you.opacity(0.13) : Track.elevated.opacity(pinned ? 1 : 0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(entry.isUser ? Track.you.opacity(0.4) : .clear, lineWidth: 1)
                }
        }
        .overlay(alignment: .leading) {
            // A lane stripe on the left edge, the way a track marks its inside
            // line. It carries the promotion/relegation zone in a league, and
            // the podium everywhere else — the top three are told apart by
            // stripe weight and type weight, never by a medal emoji.
            if let stripe = stripeTint {
                Rectangle()
                    .fill(stripe)
                    .frame(width: entry.rank == 1 ? 3 : 2)
                    .padding(.vertical, entry.rank == 1 ? 4 : 8)
            }
        }
        .shadow(color: pinned ? Color.black.opacity(0.4) : .clear, radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.rank). \(entry.isUser ? "You" : entry.racer.displayName), \(entry.points) points")
    }
}

// MARK: - Zone rule

private struct ZoneRule: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(tint.opacity(0.4))
                .frame(height: 1)
            Text(label.uppercased())
                .font(Bib.label(10))
                .labelTracking()
                .foregroundStyle(tint.opacity(0.8))
            Rectangle()
                .fill(tint.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .accessibilityLabel("\(label) line")
    }
}

// MARK: - League banner

/// The deadline. This is the thing that gets people to open the app on a Sunday
/// night, so it gets stated plainly and with a number in it.
private struct LeagueBanner: View {
    let league: League

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(league.tier.name.uppercased())
                        .font(Bib.label(13))
                        .labelTracking()
                        .foregroundStyle(league.tier.tint)
                    Text("· BRACKET OF \(league.entries.count)")
                        .font(Bib.label(11))
                        .labelTracking()
                        .foregroundStyle(Track.chalkFaint)
                }
                Text(league.urgencyLine())
                    .font(Prose.copy(16))
                    .foregroundStyle(Track.chalk)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Top \(League.promotionCount) go up. Bottom \(League.relegationCount) go down. Resets Monday.")
                    .font(Prose.caption(14))
                    .foregroundStyle(Track.chalkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Track.elevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Track.hairline, lineWidth: 1)
                }
        }
    }
}

// MARK: - Loading

/// Chalk rules that breathe. Not a spinner — a spinner in a running app is a
/// small insult.
private struct LoadingRules: View {
    @Environment(\.motion) private var motion
    @State private var start = Date()

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { i in
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    let t = motion.reduced ? 0 : timeline.date.timeIntervalSince(start)
                    let phase = (sin(t * 1.6 - Double(i) * 0.4) + 1) / 2
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Track.elevated.opacity(0.35 + 0.2 * phase))
                        .frame(height: 56)
                }
            }
        }
        .accessibilityLabel("Loading the board")
    }
}

extension Track {
    /// Leaderboard rows are not a race — nobody on them is *your* opponent right
    /// now, so they don't get opponent aqua. Only the user's row takes colour.
    static let opponentNeutral = Track.chalk.opacity(0.5)
}
