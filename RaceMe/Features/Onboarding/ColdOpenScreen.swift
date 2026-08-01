import SwiftUI

/// S0. Three seconds, then one thing to tap.
///
/// Two dots accelerate across the dark trailing light, cross a chalk line a hair
/// apart, smear into a photo finish, and the smear resolves into the wordmark.
/// It's the entire product argued in three seconds without a word of copy — and
/// it's built from the same two primitives the rest of the app is made of, so
/// the first frame a user ever sees is already teaching them the language.
struct ColdOpenScreen: View {
    var onStart: () -> Void

    @Environment(\.motion) private var motion
    @State private var start = Date()
    @State private var revealed = false

    // Beat map, in seconds.
    private let runIn: Double = 1.55       // dots accelerating toward the line
    private let cross: Double = 1.70       // the crossing
    private let smear: Double = 2.35       // trails smearing into film
    private let resolve: Double = 3.05     // film resolving into the wordmark

    var body: some View {
        ZStack {
            Track.base.ignoresSafeArea()

            if motion.reduced {
                // Reduce Motion gets the destination, not the journey: a static
                // finish frame with the wordmark already resolved.
                staticOpening
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    Canvas(opaque: false, colorMode: .extendedLinear) { ctx, size in
                        draw(ctx: &ctx, size: size, t: t)
                    }
                    .ignoresSafeArea()
                    .onChange(of: t > resolve) { _, done in
                        guard done, !revealed else { return }
                        revealed = true
                        Haptics.shared.play(.commit)
                    }
                }
            }

            VStack {
                Spacer()

                Wordmark(size: 52)
                    .opacity(wordmarkOpacity)
                    .padding(.bottom, 18)

                Text("Someone out there is running right now.")
                    .font(Body.copy(19))
                    .foregroundStyle(Track.chalkDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(revealed || motion.reduced ? 1 : 0)

                Spacer()

                // The single glass action on the screen. It carries the primary
                // morph identity, so it becomes the race-start button later
                // rather than fading out and a different button fading in.
                GlassAction(title: "Start", morphID: GlassID.primaryAction) {
                    onStart()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(revealed || motion.reduced ? 1 : 0)
                .offset(y: revealed || motion.reduced ? 0 : 20)
            }
            .animation(motion.animation(Spring.momentum), value: revealed)
        }
        .onAppear { start = Date() }
    }

    private var wordmarkOpacity: Double {
        guard !motion.reduced else { return 1 }
        return revealed ? 1 : 0
    }

    private var staticOpening: some View {
        VStack {
            Spacer()
            HStack(spacing: 3) {
                Capsule().fill(Track.you).frame(width: 46, height: 8)
                Capsule().fill(Track.them).frame(width: 34, height: 8)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    // MARK: Draw

    private func draw(ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let midY = size.height * 0.42
        let lineX = size.width * 0.62
        let laneGap: CGFloat = 26

        // Chalk line, present from the first frame — the destination is never
        // a surprise, only the margin is.
        var chalk = Path()
        chalk.move(to: CGPoint(x: lineX, y: midY - 62))
        chalk.addLine(to: CGPoint(x: lineX, y: midY + 62))
        ctx.stroke(chalk, with: .color(Track.chalk.opacity(min(0.5, t * 1.6))), lineWidth: 2)

        guard t < smear else {
            drawFilm(&ctx, size: size, midY: midY, lineX: lineX, laneGap: laneGap, t: t)
            return
        }

        // Ease-in acceleration toward the line. The dots are slowest at the
        // start and fastest at the crossing — the opposite of every generic
        // splash animation, and the reason it reads as a sprint finish.
        func x(for phase: Double, offset: Double) -> CGFloat {
            let p = min(max((t + offset) / cross, 0), 1.35)
            let eased = pow(p, 2.1)
            return -60 + CGFloat(eased) * (lineX + 140)
        }

        // Two runners, a hair apart. Warm one just ahead — the user always wins
        // the frame they're being sold.
        let racers: [(Color, Double, CGFloat)] = [
            (Track.you, 0.0, midY - laneGap / 2),
            (Track.them, -0.055, midY + laneGap / 2),
        ]

        for (color, offset, y) in racers {
            let px = x(for: t, offset: offset)
            // Trail length grows with speed. Physically that's what a long
            // exposure does, and it's what sells acceleration.
            let speed = max(0, px - x(for: t - 0.12, offset: offset))
            let tail = min(max(speed * 3.2, 18), 200)

            var trail = Path()
            trail.move(to: CGPoint(x: px - tail, y: y))
            trail.addLine(to: CGPoint(x: px, y: y))
            ctx.stroke(trail, with: .linearGradient(
                Gradient(colors: [color.opacity(0), color.opacity(0.75)]),
                startPoint: CGPoint(x: px - tail, y: y), endPoint: CGPoint(x: px, y: y)
            ), style: .init(lineWidth: 7, lineCap: .round))

            for (r, o) in [(22.0, 0.16), (12.0, 0.3)] {
                ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(o)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: px - 5, y: y - 5, width: 10, height: 10)),
                     with: .color(color))
        }
    }

    /// The trails collapse into a strip of film — the same slit-scan the app
    /// generates after every real race, arriving before the user has any idea
    /// what it is. By the time they see their own, they'll recognise it.
    private func drawFilm(_ ctx: inout GraphicsContext, size: CGSize, midY: CGFloat, lineX: CGFloat, laneGap: CGFloat, t: Double) {
        let p = min(max((t - smear) / (resolve - smear), 0), 1)
        // Film widens out of the crossing point and then fades as the wordmark
        // takes over.
        let width = size.width * (0.32 + 0.5 * CGFloat(p))
        let height: CGFloat = 74
        let x0 = lineX - width * 0.55
        let alpha = 1 - pow(p, 2.4)

        ctx.fill(
            Path(CGRect(x: x0, y: midY - height / 2, width: width, height: height)),
            with: .color(Color(hex: 0x05070E).opacity(alpha))
        )

        for (i, color) in [Track.you, Track.them].enumerated() {
            let y = midY - laneGap / 2 + CGFloat(i) * laneGap
            // A slit-scan smear: narrow, because they were moving fast.
            let centre = x0 + width * (i == 0 ? 0.46 : 0.53)
            let smearWidth = width * 0.075
            ctx.fill(
                Path(CGRect(x: centre - smearWidth / 2, y: y - 11, width: smearWidth, height: 22)),
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0), color.opacity(0.95 * alpha), color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: y - 11), endPoint: CGPoint(x: 0, y: y + 11)
                )
            )
        }
    }
}
