import SwiftUI

/// The hero of the product.
///
/// A top-down athletics lane — rust rubber, chalk markings, racers as glowing
/// dots trailing light. Not a list of names and numbers. Position on the
/// horizontal axis is distance covered.
///
/// Three decisions that make it work:
///
/// 1. **The user is pinned to the centre and the world scrolls past them.**
///    Their dot doesn't wander, so it's always in the same place at a glance,
///    but the chalk ticks streaming leftward carry the sense of travel.
///
/// 2. **The scale is compressed with `asinh`, not linear.** A literal mapping
///    makes a three-metre gap look like a dead heat and puts a two-hundred-metre
///    gap off the edge of the phone. This compression gives 1m about 9pt of
///    separation and still fits 200m on screen — close races read as close, and
///    blowouts stay legible. The side effect is a genuine perspective look, like
///    sighting down the lane, and the finish line rushing at you as you close.
///
/// 3. **Trails are drawn in world space, then compressed.** Each racer's last
///    two and a half seconds of real position, mapped through the same function.
///    Someone who just surged has a stretched trail; someone fading has a short
///    one. It's readable as speed without a single number.
struct LaneView: View {
    let engine: RaceEngine
    let participants: [Racer]
    let userID: UUID
    /// 0…1 through the final 200m. Narrows the lane and lifts the bloom.
    let closing: Double

    @Environment(\.motion) private var motion

    /// Metres at which the compression curve is roughly linear. Smaller = more
    /// separation for tiny gaps.
    private let knee: Double = 3.0
    private let unit: CGFloat = 26

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas(opaque: false, colorMode: .extendedLinear, rendersAsynchronously: false) { ctx, size in
                draw(ctx: &ctx, size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Race lane")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Scale

    /// Signed metres → signed points. `asinh` is the right curve here: it's
    /// linear near zero and logarithmic far out, with no discontinuity at the
    /// join, so a gap growing from 2m to 200m never jumps.
    private func x(_ meters: Double) -> CGFloat {
        let s: Double = meters < 0 ? -1 : 1
        return CGFloat(s * asinh(abs(meters) / knee)) * unit
    }

    // MARK: Draw

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let userDistance = engine.state(userID).distance
        let userScore = engine.state(userID).scoredPosition
        let centreX = size.width * 0.5

        // The lane block narrows slightly through the last 200m. A few points of
        // squeeze — enough to feel the walls coming in, not enough to reflow.
        let squeeze = CGFloat(closing) * 14
        let top = 18 + squeeze
        let bottom = size.height - 18 - squeeze
        let laneCount = max(participants.count, 2)
        let laneHeight = (bottom - top) / CGFloat(laneCount)

        drawSurface(&ctx, size: size, top: top, bottom: bottom)
        drawChalk(&ctx, size: size, top: top, bottom: bottom,
                  laneCount: laneCount, laneHeight: laneHeight,
                  userDistance: userDistance, centreX: centreX)
        drawFinish(&ctx, size: size, top: top, bottom: bottom,
                   userDistance: userDistance, centreX: centreX)

        // Draw opponents first so the user's dot is never occluded — the one
        // thing that must always be readable is where *you* are.
        let ordered = participants.sorted { a, b in
            (a.id == userID ? 1 : 0) < (b.id == userID ? 1 : 0)
        }
        for racer in ordered {
            guard let laneIndex = laneIndex(for: racer, laneCount: laneCount) else { continue }
            let y = bottom - laneHeight * (CGFloat(laneIndex) + 0.5)
            drawRacer(&ctx, racer: racer, y: y, centreX: centreX,
                      userScore: userScore, laneHeight: laneHeight)
        }

        drawEdgeFade(&ctx, size: size)
    }

    /// Lane assignment. The user is always lane 1 — bottom of the frame, closest
    /// to the gap readout below it, so the two read as one object.
    private func laneIndex(for racer: Racer, laneCount: Int) -> Int? {
        if racer.id == userID { return 0 }
        let opponents = participants.filter { $0.id != userID }
        guard let i = opponents.firstIndex(where: { $0.id == racer.id }) else { return nil }
        return min(i + 1, laneCount - 1)
    }

    // MARK: Surface

    private func drawSurface(_ ctx: inout GraphicsContext, size: CGSize, top: CGFloat, bottom: CGFloat) {
        let rect = CGRect(x: 0, y: top, width: size.width, height: bottom - top)
        let path = Path(roundedRect: rect, cornerRadius: 4)
        // Rust rubber, seen in the dark. Barely there — the chalk and the dots
        // carry the image, not the surface.
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [
                Track.you.opacity(0.07 + 0.05 * closing),
                Track.you.opacity(0.028),
                Track.you.opacity(0.05 + 0.04 * closing),
            ]),
            startPoint: CGPoint(x: 0, y: top),
            endPoint: CGPoint(x: 0, y: bottom)
        ))
    }

    // MARK: Chalk

    private func drawChalk(
        _ ctx: inout GraphicsContext, size: CGSize, top: CGFloat, bottom: CGFloat,
        laneCount: Int, laneHeight: CGFloat, userDistance: Double, centreX: CGFloat
    ) {
        // Lane dividers.
        var dividers = Path()
        for i in 0...laneCount {
            let y = bottom - laneHeight * CGFloat(i)
            dividers.move(to: CGPoint(x: 0, y: y))
            dividers.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.stroke(dividers, with: .color(Track.laneLine), lineWidth: 1)

        // Distance ticks in world space, so they stream past as the user moves.
        // Snapped to absolute 25m marks — not to a scrolling offset — which is
        // why the marks feel painted on the track rather than on the screen.
        //
        // Note these are always the user's *real* distance, even under handicap
        // scoring where the dots show fair position. That's the useful reading:
        // the chalk is the track you're on, the dots are the race you're in.
        let spacing: Double = 25
        let firstMark = (userDistance / spacing).rounded(.down) * spacing - spacing * 8
        var minor = Path()
        var major = Path()
        for step in 0...40 {
            let mark = firstMark + Double(step) * spacing
            guard mark >= 0, mark <= engine.distanceMeters else { continue }
            let px = centreX + x(mark - userDistance)
            guard px > -20, px < size.width + 20 else { continue }
            let isMajor = mark.truncatingRemainder(dividingBy: 100) < 0.5
            if isMajor {
                major.move(to: CGPoint(x: px, y: top))
                major.addLine(to: CGPoint(x: px, y: bottom))
            } else {
                minor.move(to: CGPoint(x: px, y: bottom - 7))
                minor.addLine(to: CGPoint(x: px, y: bottom))
                minor.move(to: CGPoint(x: px, y: top))
                minor.addLine(to: CGPoint(x: px, y: top + 7))
            }
        }
        ctx.stroke(minor, with: .color(Track.chalk.opacity(0.13)), lineWidth: 1)
        ctx.stroke(major, with: .color(Track.chalk.opacity(0.075)), lineWidth: 1)

        // Lane numerals, painted on the track at the left edge.
        for i in 0..<laneCount {
            let y = bottom - laneHeight * (CGFloat(i) + 0.5)
            var text = ctx.resolve(
                Text("\(i + 1)")
                    .font(Bib.chalk(min(laneHeight * 0.52, 20)))
                    .foregroundStyle(Track.chalk.opacity(i == 0 ? 0.30 : 0.16))
            )
            text.shading = .color(Track.chalk.opacity(i == 0 ? 0.30 : 0.16))
            ctx.draw(text, at: CGPoint(x: 13, y: y), anchor: .center)
        }
    }

    // MARK: Finish

    /// Chip mat and finish line. Enters from the right edge and accelerates
    /// toward the centre as the race closes — a direct consequence of the
    /// compression, not an effect layered on top.
    private func drawFinish(
        _ ctx: inout GraphicsContext, size: CGSize, top: CGFloat, bottom: CGFloat,
        userDistance: Double, centreX: CGFloat
    ) {
        let px = centreX + x(engine.distanceMeters - userDistance)
        guard px < size.width + 40 else { return }

        // Chip mat: the black-and-white checker band before the line.
        let matWidth: CGFloat = 14
        let cells = 6
        let cellH = (bottom - top) / CGFloat(cells)
        for row in 0..<cells {
            guard row % 2 == 0 else { continue }
            let rect = CGRect(x: px - matWidth, y: top + cellH * CGFloat(row), width: matWidth, height: cellH)
            ctx.fill(Path(rect), with: .color(Track.chalk.opacity(0.22)))
        }

        var line = Path()
        line.move(to: CGPoint(x: px, y: top - 4))
        line.addLine(to: CGPoint(x: px, y: bottom + 4))
        ctx.stroke(line, with: .color(Track.chalk.opacity(0.85)), lineWidth: 2.5)

        // The line takes on the signal colour only in the last 200m, which is the
        // one place on this screen yellow is allowed to appear.
        if closing > 0 {
            ctx.stroke(line, with: .color(Track.signal.opacity(0.75 * closing)), lineWidth: 3.5)
            // The filter goes on a *copy* of the context. `ctx` is inout, so
            // adding it here would blur every racer drawn afterwards.
            var glow = ctx
            glow.addFilter(.blur(radius: 3))
            glow.stroke(line, with: .color(Track.signal.opacity(0.35 * closing)), lineWidth: 8)
        }
    }

    // MARK: Racers

    private func drawRacer(
        _ ctx: inout GraphicsContext, racer: Racer, y: CGFloat, centreX: CGFloat,
        userScore: Double, laneHeight: CGFloat
    ) {
        let state = engine.state(racer.id)
        let isUser = racer.id == userID
        let color = racer.color

        // Screen position comes from *scored* position, so under handicap racing
        // the lane shows the fair gap and not the raw one. The dots are the truth
        // of the race, whichever truth this race is using.
        let offsetMeters = state.scoredPosition - userScore
        let px = centreX + x(offsetMeters)

        // Trail — the last 2.5s of real position, in the same frame of reference
        // as the dot, mapped through the same compression. Longer trail means
        // genuinely moving faster; a fading runner's trail shortens on its own.
        let trail = engine.trailOffsets(for: racer.id, seconds: 2.5)
        if trail.count > 3 {
            var path = Path()
            for (i, offset) in trail.enumerated() {
                let point = CGPoint(x: centreX + x(offset), y: y)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            // Three passes: wide dim glow, mid, bright core. Cheaper and far more
            // controllable than a blur filter when there's an 8.3ms frame budget.
            ctx.stroke(path, with: .color(color.opacity(0.10)), style: .init(lineWidth: laneHeight * 0.44, lineCap: .round))
            ctx.stroke(path, with: .color(color.opacity(0.22)), style: .init(lineWidth: laneHeight * 0.22, lineCap: .round))
            ctx.stroke(path, with: .color(color.opacity(0.5)), style: .init(lineWidth: 2.5, lineCap: .round))
        }

        // The dot. The user's is larger and brighter — at arm's length, in
        // daylight, moving, you find yourself first and everyone else second.
        let core: CGFloat = isUser ? 9 : 7
        let bloomScale = 1 + CGFloat(closing) * (isUser ? 0.6 : 0.25)

        for (radius, opacity) in [(core * 3.4 * bloomScale, 0.10), (core * 2.1 * bloomScale, 0.18), (core * 1.4, 0.34)] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: px - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color.opacity(opacity))
            )
        }
        ctx.fill(
            Path(ellipseIn: CGRect(x: px - core / 2, y: y - core / 2, width: core, height: core)),
            with: .color(color)
        )
        // A hot centre so the dot doesn't wash out against its own bloom.
        ctx.fill(
            Path(ellipseIn: CGRect(x: px - core / 4, y: y - core / 4, width: core / 2, height: core / 2)),
            with: .color(Track.chalk.opacity(isUser ? 0.85 : 0.5))
        )

        if state.finished {
            // A finished racer is parked on the line with a ring, not a dot that
            // keeps glowing as if they're still working.
            let r = core * 1.9
            ctx.stroke(
                Path(ellipseIn: CGRect(x: px - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(color.opacity(0.8)), lineWidth: 2
            )
        }
    }

    /// Soft edges so racers leave and enter the frame rather than being clipped.
    private func drawEdgeFade(_ ctx: inout GraphicsContext, size: CGSize) {
        let w: CGFloat = 34
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: size.height)),
            with: .linearGradient(
                Gradient(colors: [Track.base, Track.base.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: 0)
            )
        )
        ctx.fill(
            Path(CGRect(x: size.width - w, y: 0, width: w, height: size.height)),
            with: .linearGradient(
                Gradient(colors: [Track.base.opacity(0), Track.base]),
                startPoint: CGPoint(x: size.width - w, y: 0), endPoint: CGPoint(x: size.width, y: 0)
            )
        )
    }

    // MARK: Accessibility

    /// The lane is a picture, and a picture needs to be sayable. VoiceOver gets
    /// the same information the dots carry.
    private var accessibilitySummary: String {
        let user = engine.state(userID)
        guard let headline = engine.headlineGap,
              let opponent = participants.first(where: { $0.id == headline.opponent })
        else { return "Position \(user.place)." }
        let m = Int(abs(headline.meters).rounded())
        return headline.meters >= 0
            ? "You lead \(opponent.displayName) by \(m) metres."
            : "\(opponent.displayName) leads you by \(m) metres."
    }
}
