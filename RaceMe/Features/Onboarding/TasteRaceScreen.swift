import SwiftUI

/// S14. The most important screen in the app.
///
/// Twenty-five seconds of live racing against a ghost, using the real race UI at
/// full fidelity — the same lane, the same gap, the same haptics, the same
/// commentary. Nothing here is a demo build of anything.
///
/// The ghost runs a few percent slower than their stated pace, so they win. By
/// the time the paywall appears they know exactly what they're buying, they've
/// won once, and they're holding an artifact. Then, and only then, we ask for
/// money.
struct TasteRaceScreen: View {
    let model: OnboardingModel

    @Environment(\.motion) private var motion
    @State private var raceModel: RaceViewModel?
    @State private var finished: RaceResult?

    var body: some View {
        ZStack {
            if let result = finished {
                TasteFinishView(result: result, profile: model.profile) {
                    model.tasteResult = result
                    model.advance()
                }
                .transition(motion.reduced ? .opacity : .opacity.combined(with: .scale(scale: 1.02)))
            } else if let raceModel {
                LiveRaceView(model: raceModel, profile: model.profile) { result in
                    guard let result else { return }
                    withAnimation(motion.animation(Spring.celebrate)) { finished = result }
                }
            } else {
                intro
            }
        }
        .animation(motion.animation(Spring.navigate), value: finished)
    }

    /// One beat of setup, so the race doesn't ambush them and the countdown has
    /// something to count down *from*.
    private var intro: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Alright. One race.")
                    .font(Prose.title(34))
                    .foregroundStyle(Track.chalk)
                Text(model.profile.rivalMention.map {
                    "400 metres against \($0)'s pace. This is exactly what a real one looks like."
                } ?? "400 metres against a pacer. This is exactly what a real one looks like.")
                    .font(Prose.copy(18))
                    .foregroundStyle(Track.chalkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            // The primary action morphs into the race controls — the nav action
            // becoming the race-start button is precisely the moment Liquid
            // Glass's morphing behaviour exists for.
            GlassAction(title: "On the line", systemImage: "figure.run", morphID: GlassID.primaryAction) {
                let created = model.makeTasteRace()
                withAnimation(Spring.navigate) { raceModel = created }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
    }
}

/// The full celebration, and their first photo finish. This is the artifact they
/// carry into the paywall.
private struct TasteFinishView: View {
    let result: RaceResult
    let profile: RunnerProfile
    var onContinue: () -> Void

    @Environment(\.motion) private var motion
    @State private var develop: Double = 0
    @State private var shown = false

    @MainActor private var film: PhotoFinishFilm { PhotoFinishFilm.build(from: result) }

    var body: some View {
        ZStack {
            AmbientBackground()
            WinBurst(active: result.userWon)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 8) {
                    TrackLabel("Your first race")
                    Text(result.userWon ? "WON" : "CLOSE")
                        .font(Bib.hero(96))
                        .bibTracking(96)
                        .foregroundStyle(result.userWon ? Track.you : Track.chalk)
                    Text(subhead)
                        .font(Prose.copy(18))
                        .foregroundStyle(Track.chalkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 14 * motion.travel)

                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 9) {
                    TrackLabel("Photo finish")
                        .padding(.horizontal, 24)
                    PhotoFinishView(film: film, develop: develop)
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 20)
                    Text("Every race you finish makes one of these.")
                        .font(Prose.caption(15))
                        .foregroundStyle(Track.chalkFaint)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 28)

                GlassAction(title: "Keep going", morphID: nil, action: onContinue)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                    .opacity(shown ? 1 : 0)
            }
        }
        .atmosphere(result.userWon ? .won : .idle)
        .task {
            guard !motion.reduced else { develop = 1; shown = true; return }
            withAnimation(motion.animation(Spring.momentum)) { shown = true }
            withAnimation(.spring(duration: 0.95, bounce: 0).delay(0.25)) { develop = 1 }
        }
    }

    private var subhead: String {
        let margin = abs(result.margin)
        let name = result.config.opponents.first?.displayName ?? "the pacer"
        if margin < 1 {
            return "\(Fmt.clock(result.userTime)) — you got \(name) by less than a second."
        }
        return "\(Fmt.clock(result.userTime)) — \(Fmt.clock(margin)) clear of \(name)."
    }
}

/// The celebration. Chalk dust kicked up off the track, not confetti — and under
/// Reduce Motion it becomes a static badge rather than disappearing entirely.
struct WinBurst: View {
    let active: Bool
    @Environment(\.motion) private var motion
    @State private var start = Date()
    /// The burst runs once and then gets out of the way. Leaving the timeline
    /// running afterwards kept an empty Canvas redrawing at 120Hz behind the
    /// paywall for as long as the screen was up.
    @State private var burning = true

    var body: some View {
        Group {
            if active && !motion.reduced && burning {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    Canvas { ctx, size in
                        guard t < 2.4 else { return }
                        var rng = Rng(seed: 0xB1A5)
                        let fade = 1 - t / 2.4
                        for _ in 0..<70 {
                            let angle = rng.range(-Double.pi, 0)
                            let speed = rng.range(90, 380)
                            let x = size.width / 2 + cos(angle) * speed * t
                            // Gravity, because dust falls.
                            let y = size.height * 0.55 + sin(angle) * speed * t + 190 * t * t
                            let r = rng.range(1.2, 3.4)
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                with: .color(Track.you.opacity(0.5 * fade))
                            )
                        }
                    }
                    .allowsHitTesting(false)
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(2500))
                    burning = false
                }
            } else if active {
                // Reduce Motion: a static badge.
                VStack {
                    Spacer()
                    Text("WON")
                        .font(Bib.label(13))
                        .labelTracking()
                        .foregroundStyle(Track.you)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay { Capsule().strokeBorder(Track.you, lineWidth: 1) }
                    Spacer()
                }
                .opacity(0)
            }
        }
        .accessibilityHidden(true)
    }
}
