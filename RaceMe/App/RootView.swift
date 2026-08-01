import SwiftUI

/// The shell.
///
/// One glass tab bar, one full-screen race, and everything else underneath it.
/// A race takes the whole screen because a race takes the whole person.
struct RootView: View {
    @State private var app = AppState()
    @Namespace private var glassNS

    var body: some View {
        ZStack {
            AmbientBackground()

            if app.profile.completedOnboarding {
                main
            } else {
                OnboardingFlow(
                    model: OnboardingModel(profile: app.profile, services: app.services),
                    onFinish: { staged in
                        // Land on a populated home. The staged race arrives from
                        // the compute screen, so there's never a frame where a
                        // brand-new user sees an empty hero.
                        app.stagedRace = staged
                        app.saveProfile()
                        Notifications.scheduleRunReminders(for: app.profile)
                        Task { await app.refresh() }
                    }
                )
                .transition(.opacity)
            }
        }
        // The single biggest move in the app — out of the flow and into the
        // product — and it was a hard cut. The tab bar and the hero card now
        // arrive under a spring while the paywall leaves.
        .animation(Spring.navigate, value: app.profile.completedOnboarding)
        .environment(\.glassNamespace, glassNS)
        .providesMotionPreference()
        .preferredColorScheme(.dark)
        .task { app.start() }
        .onOpenURL { app.handle(url: $0) }
        // A race takes over completely: no tab bar, no status bar, nothing to
        // tap by accident with a sweaty thumb.
        .fullScreenCover(item: Binding(
            get: { app.activeRace.map { RaceSession(model: $0) } },
            set: { if $0 == nil { app.activeRace = nil } }
        )) { session in
            LiveRaceView(model: session.model, profile: app.profile) { result in
                app.endRacePresentation(with: result)
            }
            .environment(\.glassNamespace, glassNS)
            .providesMotionPreference()
        }
        .fullScreenCover(item: $app.postRace) { result in
            PostRaceView(
                result: result,
                profile: app.profile,
                onRematch: {
                    app.postRace = nil
                    app.rematch(result)
                },
                onDone: { app.postRace = nil }
            )
            .environment(\.glassNamespace, glassNS)
            .providesMotionPreference()
        }
        .fullScreenCover(item: $app.spectating) { race in
            SpectateView(app: app, race: race) { app.spectating = nil }
                .environment(\.glassNamespace, glassNS)
                .providesMotionPreference()
        }
        .sheet(item: $app.pendingChallenge) { challenge in
            ChallengeSheet(
                challenge: challenge,
                onAccept: { app.acceptPendingChallenge() },
                onDismiss: { app.pendingChallenge = nil }
            )
            .presentationDetents([.height(400)])
            .presentationBackground(.clear)
            .providesMotionPreference()
        }
    }

    private var main: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch app.tab {
                case .home: HomeView(app: app)
                case .board: LeaderboardView(app: app)
                case .you: ProfileView(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            RaceTabBar(selection: $app.tab)
                .padding(.bottom, 6)
        }
    }
}

/// Wrapper so `fullScreenCover(item:)` has something Identifiable to hang on to.
private struct RaceSession: Identifiable {
    let model: RaceViewModel
    var id: UUID { model.config.id }
}

/// `RaceResult` and `LiveRace` already carry identity. `Challenge` arrives from a
/// URL and has none, so it gets one derived from its contents.
extension Challenge: Identifiable {
    var id: String { "\(fromHandle)-\(distanceMeters)-\(seed)" }
}

// MARK: - Tab bar

/// Glass, because it's floating chrome that content scrolls underneath. Three
/// destinations, named for what's in them rather than for a shape.
struct RaceTabBar: View {
    @Binding var selection: AppState.Tab
    @Environment(\.motion) private var motion
    @Environment(\.glassNamespace) private var glassNS
    @Namespace private var indicator

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(AppState.Tab.allCases) { tab in
                    Button {
                        guard tab != selection else { return }
                        Haptics.shared.play(.select)
                        withAnimation(motion.animation(Spring.snap)) { selection = tab }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .bold))
                            Text(tab.label)
                                .font(Bib.label(10))
                                .labelTracking()
                        }
                        .foregroundStyle(selection == tab ? Track.chalk : Track.chalkFaint)
                        .frame(width: 74, height: 46)
                        .background {
                            if selection == tab {
                                // The indicator travels between tabs rather than
                                // fading out here and in over there.
                                Capsule()
                                    .fill(Track.you.opacity(0.22))
                                    .matchedGeometryEffect(id: "tabIndicator", in: indicator)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable(scale: 0.94, haptic: nil))
                    .accessibilityLabel(tab.label.capitalized)
                    .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(5)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID(GlassID.tabBar, in: glassNS)
        }
    }
}

// MARK: - Challenge sheet

/// Where a tapped link lands. Pre-configured, with their name on it, and one
/// action.
struct ChallengeSheet: View {
    let challenge: Challenge
    var onAccept: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Track.base.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 20)

                TrackLabel("Challenge")
                Text(challenge.headline)
                    .font(Body.title(30))
                    .foregroundStyle(Track.chalk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Text(challenge.subhead)
                    .font(Body.copy(17))
                    .foregroundStyle(Track.chalkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Spacer(minLength: 20)

                HStack(spacing: 0) {
                    stat("DISTANCE", Fmt.raceName(challenge.distanceMeters))
                    stat("THEIR PACE", Fmt.pace(challenge.paceSecPerKm) + "/km")
                    if let t = challenge.timeSeconds {
                        stat("TO BEAT", Fmt.clock(t))
                    }
                }

                Spacer(minLength: 20)

                GlassAction(title: "Take it", systemImage: "figure.run", morphID: GlassID.primaryAction) {
                    onAccept()
                }
                QuietAction(title: "Not now", action: onDismiss)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            TrackLabel(label, size: 10)
            Text(value)
                .font(Bib.numeral(24))
                .bibTracking(24)
                .foregroundStyle(Track.chalk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
