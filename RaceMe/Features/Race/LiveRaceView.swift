import SwiftUI

/// The screen everything else in the app borrows from.
///
/// Designed for exactly one reader: someone at arm's length, in daylight, while
/// moving, breathing hard. Every decision here is downstream of that and of
/// nothing else — no hover states, no small text, no colour that needs thinking
/// about, and only two glass surfaces on screen at any moment.
///
/// Reading down: what race this is, where everyone is, how much you're winning
/// or losing by, your own numbers, who else is out there, what just happened,
/// and what you can do about it.
struct LiveRaceView: View {
    @State var model: RaceViewModel
    let profile: RunnerProfile
    var onExit: (RaceResult?) -> Void

    @Environment(\.motion) private var motion
    @Environment(\.glassNamespace) private var glassNS
    @State private var didAppear = false

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 6)

                if let fault = model.fault {
                    FaultBanner(fault: fault)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                Spacer(minLength: 10)

                // The hero. Given roughly a third of the screen — enough that
                // it's obviously the subject, not enough to push the gap below
                // the fold on a small phone.
                LaneView(
                    engine: model.engine,
                    participants: model.config.participants,
                    userID: model.config.user.id,
                    closing: model.engine.closingProgress
                )
                .frame(height: laneHeight)
                .padding(.top, 4)

                Spacer(minLength: 6)

                GapReadout(
                    engine: model.engine,
                    opponent: headlineOpponent,
                    scoring: model.config.scoring,
                    closing: model.engine.closingProgress
                )

                Spacer(minLength: 10)

                RaceStatRow(engine: model.engine, unit: profile.unit)
                    .padding(.horizontal, 20)

                if !model.opponentsByPlace.isEmpty {
                    OpponentStrip(
                        engine: model.engine,
                        opponents: model.config.opponents,
                        standings: model.standings,
                        scoring: model.config.scoring
                    )
                    .padding(.top, 18)
                }

                CommentaryTicker(events: model.events)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer(minLength: 88)
            }

            ReactionBurst(reactions: model.liveReactions)
                .offset(y: -140)

            countdownLayer
        }
        .atmosphere(model.atmosphere)
        .safeAreaInset(edge: .bottom) { controlBar }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            guard !didAppear else { return }
            didAppear = true
            model.beginCountdown()
        }
        .onDisappear { model.teardown() }
        .onChange(of: model.result) { _, result in
            guard let result else { return }
            onExit(result)
        }
        .confirmationDialog(
            "End this race?",
            isPresented: $model.confirmingEnd,
            titleVisibility: .visible
        ) {
            Button("End it", role: .destructive) { model.endEarly() }
            Button("Keep running", role: .cancel) { model.confirmingEnd = false }
        } message: {
            // Says what happens, not "are you sure".
            Text("It won't count as a loss, and it won't count as a time.")
        }
    }

    // MARK: Header

    /// Glass surface one of two. Short, floating, no more than a handful of
    /// words — race identity and the clock, nothing that needs reading.
    private var header: some View {
        // A clock that ticks once a second doesn't need 120 frames to do it.
        // Those frames belong to the lane.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            // Untinted, always. During the final 200m the finish line on the
            // lane goes yellow, and that has to be the only yellow on screen or
            // it stops meaning "this is the thing that matters".
            GlassPill(morphID: GlassID.headerPill) {
                HStack(spacing: 10) {
                    Text(model.headerTitle)
                        .font(Bib.label(14))
                        .labelTracking()
                        .foregroundStyle(Track.chalk)

                    dot
                    Text(model.config.mode.shortLabel)
                        .font(Bib.label(14))
                        .labelTracking()
                        .foregroundStyle(Track.chalkDim)

                    dot
                    Text(Fmt.clock(model.engine.elapsed))
                        .font(Bib.mono(15, weight: .bold))
                        .foregroundStyle(Track.chalk)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dot: some View {
        Circle().fill(Track.chalkFaint).frame(width: 3, height: 3)
    }

    // MARK: Controls

    /// Glass surface two of two. One container, so the three controls merge and
    /// refract as a single piece of material rather than three stuck-on panes.
    private var controlBar: some View {
        GlassControlBar(spacing: 12) {
            GlassCircleButton(
                systemImage: model.isPaused ? "play.fill" : "pause.fill",
                size: 56,
                haptic: .commit,
                accessibilityName: model.isPaused ? "Resume race" : "Pause race"
            ) {
                model.isPaused ? model.resume() : model.pause()
            }

            GlassCircleButton(
                systemImage: "flame.fill",
                size: 56,
                haptic: .reaction,
                accessibilityName: "Send a flare to your opponents"
            ) {
                // Your opponents see this land on their screen. Mid-race
                // reactions are what make running feel watched.
                model.receive(Reaction(from: profile.handle.isEmpty ? "you" : profile.handle, at: Date()))
            }

            GlassCircleButton(
                systemImage: "stop.fill",
                tint: Track.them,
                size: 56,
                haptic: .select,
                accessibilityName: "End race"
            ) {
                model.requestEnd()
            }
        }
        .padding(.bottom, 10)
        .opacity(model.isRunning ? 1 : 0)
        .animation(motion.animation(Spring.ui), value: model.isRunning)
    }

    // MARK: Countdown

    @ViewBuilder
    private var countdownLayer: some View {
        switch model.phase {
        case .countdown(let n):
            CountdownOverlay(value: n)
                .transition(motion.reduced ? .opacity : .opacity.combined(with: .scale(scale: 1.1)))
        case .running where model.engine.elapsed < 0.5:
            GoFlash()
        default:
            EmptyView()
        }
    }

    // MARK: Geometry

    /// The lane gets a third of the screen, floored so it never collapses on a
    /// small device and the chalk stays readable.
    private var laneHeight: CGFloat {
        let lanes = max(model.config.participants.count, 2)
        return min(max(CGFloat(lanes) * 52 + 30, 150), 250)
    }

    private var headlineOpponent: Racer? {
        guard let headline = model.engine.headlineGap else { return nil }
        return model.config.participants.first { $0.id == headline.opponent }
    }
}
