import SwiftUI

/// S3. The highest-friction question in the flow, defused.
///
/// It's a drag, not a picker — a picker asks you to commit to a number, and a
/// drag asks you to point at roughly where you are. A runner pictogram changes
/// cadence in real time under your thumb, and the label moves through
/// Conversational → Working → Hurting → Not talking to anyone, so the answer is
/// legible as an *effort* even to someone who has never looked at a watch.
///
/// And underneath, quietly: we'll learn this from your runs anyway. Which is
/// true — `RunnerProfile.handicapPaceSecPerKm` switches to observed pace the
/// moment there's a real run to observe.
struct PaceScreen: View {
    let profile: RunnerProfile
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @State private var seconds: Double = 570      // 9:30 / mile
    @State private var dragging = false
    @State private var lastHapticBucket = 0

    private let minSeconds: Double = 330          // 5:30
    private let maxSeconds: Double = 900          // 15:00

    private var normalized: Double {
        (seconds - minSeconds) / (maxSeconds - minSeconds)
    }

    /// Cadence in steps per second. Real running cadence barely varies with pace
    /// — it's stride *length* that changes — so the pictogram's legs speed up
    /// only mildly and the whole figure leans instead. Getting that right is the
    /// difference between a runner and a cartoon.
    private var cadence: Double { 2.9 - normalized * 0.55 }

    private var effortLabel: String {
        switch normalized {
        case ..<0.22: "Not talking to anyone"
        case ..<0.45: "Hurting"
        case ..<0.72: "Working"
        default: "Conversational"
        }
    }

    private var effortColor: Color {
        normalized < 0.22 ? Track.you : normalized < 0.45 ? Track.you.opacity(0.8) : Track.chalk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("How fast is a comfortable mile for you?")
                    .font(Prose.title(32))
                    .foregroundStyle(Track.chalk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 18)

            RunnerPictogram(cadence: cadence, lean: normalized, running: true)
                .frame(height: 118)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 14)

            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.pace(seconds / 1.609344, unit: .mi))
                        .font(Bib.hero(84))
                        .bibTracking(84)
                        .foregroundStyle(Track.chalk)
                        .contentTransition(.numericText(value: seconds))
                    Text("/ MILE")
                        .font(Bib.label(14))
                        .labelTracking()
                        .foregroundStyle(Track.chalkFaint)
                }

                Text(effortLabel)
                    .font(Prose.headline(19))
                    .foregroundStyle(effortColor)
                    .contentTransition(.opacity)
                    .animation(motion.animation(Spring.snap), value: effortLabel)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 18)

            paceTrack
                .padding(.horizontal, 24)

            Text("We'll learn this from your runs anyway.")
                .font(Prose.caption(15))
                .foregroundStyle(Track.chalkFaint)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Spacer(minLength: 20)

            GlassAction(title: "That's about right", morphID: nil) {
                profile.comfortableMileSeconds = seconds
                onDone()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .onAppear { seconds = profile.comfortableMileSeconds }
    }

    // MARK: The drag control

    /// A stretch of lane with a chalk marker on it. Tracks the thumb one to one
    /// and stays under it — no snapping to the nearest whole number while you're
    /// still holding on.
    private var paceTrack: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = w * normalized

            ZStack(alignment: .leading) {
                // Lane surface with chalk ticks.
                Canvas { ctx, size in
                    ctx.fill(
                        Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8),
                        with: .color(Track.you.opacity(0.07))
                    )
                    var ticks = Path()
                    for i in 0...12 {
                        let tx = size.width * CGFloat(i) / 12
                        let tall = i % 3 == 0
                        ticks.move(to: CGPoint(x: tx, y: size.height))
                        ticks.addLine(to: CGPoint(x: tx, y: size.height - (tall ? 14 : 7)))
                    }
                    ctx.stroke(ticks, with: .color(Track.chalk.opacity(0.18)), lineWidth: 1)
                }

                // Marker.
                Capsule()
                    .fill(Track.you)
                    .frame(width: 6, height: 58)
                    .shadow(color: Track.you.opacity(0.5), radius: dragging ? 16 : 8)
                    .scaleEffect(x: dragging ? 1.25 : 1, y: dragging ? 1.06 : 1, anchor: .center)
                    .offset(x: min(max(x - 3, 0), w - 6))
                    .animation(motion.animation(Spring.snap), value: dragging)
            }
            .frame(height: 58)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        let t = min(max(value.location.x / w, 0), 1)
                        seconds = minSeconds + t * (maxSeconds - minSeconds)
                        tickHaptic()
                    }
                    .onEnded { _ in
                        dragging = false
                        Haptics.shared.play(.commit)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Comfortable mile pace")
            .accessibilityValue("\(Fmt.pace(seconds / 1.609344, unit: .mi)) per mile, \(effortLabel)")
            .accessibilityAdjustableAction { direction in
                seconds += direction == .increment ? -5 : 5
                seconds = min(max(seconds, minSeconds), maxSeconds)
                Haptics.shared.play(.select)
            }
        }
        .frame(height: 58)
    }

    /// One light tick per fifteen seconds of pace. Enough to feel the scale
    /// under your thumb, not so much that it buzzes continuously.
    private func tickHaptic() {
        let bucket = Int(seconds / 15)
        guard bucket != lastHapticBucket else { return }
        lastHapticBucket = bucket
        Haptics.shared.play(.select)
    }
}

// MARK: - Pictogram

/// The runner. Built from the same vocabulary as race signage — flat, angular,
/// stroked, no face, no shading. It runs at the cadence you set and leans
/// further forward the harder the effort. Nothing cute about it.
struct RunnerPictogram: View {
    /// Steps per second.
    let cadence: Double
    /// 0…1, slow to fast. Drives forward lean and stride length.
    let lean: Double
    var running: Bool = true

    @Environment(\.motion) private var motion
    @State private var start = Date()

    var body: some View {
        Group {
            if motion.reduced {
                // Reduce Motion: a static mid-stride pose, not a frozen frame of
                // a gait cycle that happens to look broken.
                Canvas { ctx, size in draw(ctx: &ctx, size: size, phase: 0.6) }
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    Canvas { ctx, size in
                        draw(ctx: &ctx, size: size, phase: t * cadence)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, phase: Double) {
        let s = min(size.height / 120, size.width / 120)
        let cx = size.width / 2
        let cy = size.height / 2
        let stroke = 7 * s
        // Effort tilts the whole figure forward. `lean` arrives 0 = fast.
        let tilt = (1 - lean) * 0.26

        func p(_ x: Double, _ y: Double) -> CGPoint {
            // Rotate about the hip so the lean reads as posture, not a slide.
            let dx = x * s, dy = y * s
            let c = cos(tilt), sn = sin(tilt)
            return CGPoint(x: cx + dx * c - dy * sn, y: cy + dx * sn + dy * c)
        }

        let swing = sin(phase * 2 * .pi)
        let counter = sin(phase * 2 * .pi + .pi)
        // Stride length grows with speed; cadence barely does. That's how real
        // running works, and it's why the fast end reads as *covering ground*.
        let reach = 22 + (1 - lean) * 16
        let bob = cos(phase * 4 * .pi) * 3 * s

        var body = Path()
        // Torso
        body.move(to: p(-4, 6 + bob / s))
        body.addLine(to: p(6, -26 + bob / s))
        // Front arm
        body.move(to: p(4, -20 + bob / s))
        body.addLine(to: p(4 + counter * 16, -32 - abs(counter) * 6 + bob / s))
        // Back arm
        body.move(to: p(4, -20 + bob / s))
        body.addLine(to: p(4 + swing * 16, -6 + abs(swing) * 4 + bob / s))
        // Front leg
        body.move(to: p(-4, 6 + bob / s))
        body.addLine(to: p(-4 + swing * reach * 0.55, 24 - abs(swing) * 10 + bob / s))
        body.addLine(to: p(-4 + swing * reach, 40 + bob / s))
        // Back leg
        body.move(to: p(-4, 6 + bob / s))
        body.addLine(to: p(-4 + counter * reach * 0.55, 24 - abs(counter) * 10 + bob / s))
        body.addLine(to: p(-4 + counter * reach, 40 + bob / s))

        ctx.stroke(body, with: .color(Track.you), style: .init(lineWidth: stroke, lineCap: .round, lineJoin: .round))

        // Head
        let head = 9.5 * s
        let hp = p(9, -34 + bob / s)
        ctx.fill(Path(ellipseIn: CGRect(x: hp.x - head, y: hp.y - head, width: head * 2, height: head * 2)),
                 with: .color(Track.you))

        // Ground chalk, so the figure has something to push off.
        var ground = Path()
        ground.move(to: CGPoint(x: cx - 58 * s, y: cy + 46 * s))
        ground.addLine(to: CGPoint(x: cx + 58 * s, y: cy + 46 * s))
        ctx.stroke(ground, with: .color(Track.chalk.opacity(0.16)), lineWidth: 1)
    }
}
