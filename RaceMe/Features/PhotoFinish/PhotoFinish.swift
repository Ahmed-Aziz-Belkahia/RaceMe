import SwiftUI

/// The post-race hero, the history thumbnail, and the share card — all the same
/// object, drawn from real race data.
///
/// This is a genuine slit-scan, the way a photo-finish camera works. A real one
/// has no lens pointed down the track: it stares at a one-pixel-wide slit
/// **at the line** and streaks whatever passes through it onto film that's
/// moving sideways. So the horizontal axis of the image is not space — it's
/// **time**. A runner who crossed earlier appears further left. A faster runner
/// spends less time in the slit and comes out narrow; a slower one smears wide.
///
/// That's what's computed here: for every column of the image, how much of each
/// racer's body was in the slit at that instant, taken from the positions the
/// engine actually sampled at 60Hz through the finish. Nothing about the shape
/// of these smears is decoration — swap the race and you get a different picture.
struct PhotoFinishFilm {
    struct Lane {
        let id: UUID
        let name: String
        let color: Color
        let isUser: Bool
        /// Elapsed seconds at which they crossed. Nil if they never did.
        let crossedAt: Double?
        /// Speed in m/s as they crossed. Used to carry them *through* the slit —
        /// the engine parks a finished racer exactly on the line, and without
        /// this they'd keep printing forever.
        let speedAtLine: Double
        /// Nil if their crossing falls outside the visible window — the view
        /// draws an edge marker instead of silently cropping them out.
        let inWindow: Bool
    }

    let lanes: [Lane]
    let samples: [FinishSample]
    let finishDistance: Double
    /// Visible time window.
    let t0: Double
    let t1: Double
    var duration: Double { max(t1 - t0, 0.001) }

    /// Effective depth of the slit in metres. A real one is millimetres wide and
    /// the runner's own body provides the width; this is that, rounded up to
    /// something that survives being 40 points tall on a history thumbnail. The
    /// *ratios* between racers stay exactly true, which is what carries the
    /// information.
    static let bodyDepth: Double = 1.5

    /// Longest window we'll show. Past this, a blowout compresses everyone into
    /// a hairline and the picture stops meaning anything — so we clamp and mark
    /// the stragglers at the edge instead.
    static let maxWindow: Double = 6.5

    var hasImage: Bool { samples.count > 3 && lanes.contains { $0.crossedAt != nil } }

    // MARK: Build

    /// Films are memoised by race.
    ///
    /// `build` walks every sample once per racer to find crossings, and it was
    /// being called from view bodies — so the post-race develop animation
    /// rebuilt the whole thing sixty times a second, and a history list rebuilt
    /// one per row per scroll frame. The data is immutable once a race is over,
    /// so it only ever needs computing once.
    @MainActor private static var cache: [UUID: PhotoFinishFilm] = [:]
    @MainActor private static var cacheOrder: [UUID] = []
    private static let cacheLimit = 24

    @MainActor
    static func build(from result: RaceResult) -> PhotoFinishFilm {
        if let hit = cache[result.id] { return hit }
        let film = compute(from: result)
        cache[result.id] = film
        cacheOrder.append(result.id)
        if cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache[evicted] = nil
        }
        return film
    }

    private static func compute(from result: RaceResult) -> PhotoFinishFilm {
        let distance = result.config.distanceMeters
        let samples = result.finishSamples.sorted { $0.t < $1.t }

        // Crossing time per racer: the instant their sampled distance passes the
        // line, linearly interpolated between the two straddling samples. This is
        // the same interpolation the engine used for the official time, so the
        // picture and the clock agree.
        var crossings: [UUID: Double] = [:]
        var speeds: [UUID: Double] = [:]
        for racer in result.config.participants {
            var previous: (t: Double, d: Double)?
            for sample in samples {
                guard let d = sample.distances[racer.id] else { continue }
                if d >= distance, let p = previous, p.d < distance {
                    let span = d - p.d
                    let dt = sample.t - p.t
                    let f = span > 0 ? (distance - p.d) / span : 0
                    crossings[racer.id] = p.t + dt * f
                    if dt > 0 { speeds[racer.id] = span / dt }
                    break
                }
                previous = (sample.t, d)
            }
            // Fall back to the recorded time if the sample window missed it.
            if crossings[racer.id] == nil, let t = result.times[racer.id] {
                crossings[racer.id] = t
            }
            // Fall back to average pace for the leg if the straddle was missed.
            if speeds[racer.id] == nil, let t = result.times[racer.id], t > 0 {
                speeds[racer.id] = distance / t
            }
        }

        let times = crossings.values.sorted()
        let first = times.first ?? 0

        // Pad either side so nobody is flush against the edge of the film.
        let pad = 0.55
        let t0 = max(first - pad, samples.first?.t ?? first - pad)

        // The window closes on the last runner who's actually *in* it. Sizing it
        // to a straggler forty seconds back would leave the winner as a hairline
        // at the far left and the rest of the frame empty — so anyone beyond the
        // window gets an edge tag instead, and the film tightens around the
        // people who were genuinely at the line together.
        let contested = times.filter { $0 - first <= maxWindow }
        let last = contested.last ?? first
        let t1 = min(max(last + pad, t0 + 1.6), t0 + maxWindow)

        let lanes: [Lane] = result.order.compactMap { id in
            guard let racer = result.config.participants.first(where: { $0.id == id }) else { return nil }
            let crossed = crossings[id]
            return Lane(
                id: id,
                name: racer.isUser ? "YOU" : racer.displayName.uppercased(),
                color: racer.color,
                isUser: racer.isUser,
                crossedAt: crossed,
                speedAtLine: max(speeds[id] ?? 4, 1.5),
                inWindow: crossed.map { $0 >= t0 && $0 <= t1 } ?? false
            )
        }

        return PhotoFinishFilm(
            lanes: lanes, samples: samples, finishDistance: distance, t0: t0, t1: t1
        )
    }

    // MARK: Sampling

    /// How much of this racer's body is in the slit at time `t`, 0…1.
    ///
    /// Gaussian falloff around the line. A runner moving fast passes through the
    /// whole distribution in a few hundredths of a second and prints narrow; a
    /// runner limping in prints wide. That difference is the whole picture.
    func intensity(_ id: UUID, at t: Double) -> Double {
        guard let lane = lanes.first(where: { $0.id == id }) else { return 0 }

        // Past the line, position is extrapolated from the speed they crossed
        // at rather than read from the samples. The engine parks a finisher
        // exactly on the line and leaves them there, so sampled distance stays
        // pinned at the finish distance — which reads as "still in the slit"
        // and printed one solid slab across the whole frame.
        let d: Double
        if let crossed = lane.crossedAt, t > crossed {
            d = finishDistance + lane.speedAtLine * (t - crossed)
        } else if let sampled = distance(of: id, at: t) {
            d = sampled
        } else {
            return 0
        }

        let e = d - finishDistance
        let sigma = Self.bodyDepth / 2
        let z = e / sigma
        guard abs(z) < 3 else { return 0 }
        return exp(-z * z)
    }

    /// Interpolated distance for a racer at an arbitrary time.
    private func distance(of id: UUID, at t: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        if t <= samples[0].t { return samples[0].distances[id] }
        if t >= samples[samples.count - 1].t { return samples[samples.count - 1].distances[id] }

        // Binary search — this is called once per column per racer, and a share
        // card is 1080 columns wide.
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        guard let a = samples[lo].distances[id], let b = samples[hi].distances[id] else { return nil }
        let span = samples[hi].t - samples[lo].t
        let f = span > 0 ? (t - samples[lo].t) / span : 0
        return a + (b - a) * f
    }

    /// Margin between the winner and whoever was next, in seconds.
    var winningMargin: Double? {
        let times = lanes.compactMap(\.crossedAt).sorted()
        guard times.count > 1 else { return nil }
        return times[1] - times[0]
    }
}

// MARK: - View

/// Draws the film.
///
/// `develop` runs 0 → 1 and wipes the image in from the left, the way a print
/// comes up in a tray. On the post-race screen that's the reveal; everywhere
/// else it's just left at 1.
struct PhotoFinishView: View {
    let film: PhotoFinishFilm
    /// 0…1. The develop wipe.
    var develop: Double = 1
    /// Names, timecode, and the winner's marker. Off for thumbnails.
    var showsChrome: Bool = true
    /// Column resolution. Thumbnails don't need 800 samples.
    var columns: Int = 420

    var body: some View {
        Canvas(opaque: false, colorMode: .extendedLinear) { ctx, size in
            guard film.hasImage else {
                drawUnexposed(&ctx, size: size)
                return
            }
            drawFilmBase(&ctx, size: size)
            drawSmears(&ctx, size: size)
            if showsChrome {
                drawChrome(&ctx, size: size)
            }
            drawUndeveloped(&ctx, size: size)
        }
        .background(Color(hex: 0x05070E))
        .accessibilityElement()
        .accessibilityLabel("Photo finish")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Layers

    private func drawFilmBase(_ ctx: inout GraphicsContext, size: CGSize) {
        // Unexposed film isn't black — it's a very dark warm base with visible
        // grain, and that's what makes the smears read as light *on* something.
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Color(hex: 0x080A12), Color(hex: 0x05070E), Color(hex: 0x090B14)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
        ))

        // Sprocket rails, top and bottom. The single most recognisable thing
        // about a strip of film, and it costs eight lines.
        let rail: CGFloat = max(size.height * 0.045, 3)
        for y in [CGFloat(0), size.height - rail] {
            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rail)),
                     with: .color(Color(hex: 0x0D1120)))
        }
        let hole = rail * 0.55
        var holes = Path()
        var x: CGFloat = hole
        while x < size.width {
            holes.addRoundedRect(in: CGRect(x: x, y: rail * 0.22, width: hole, height: hole),
                                 cornerSize: CGSize(width: 1, height: 1))
            holes.addRoundedRect(in: CGRect(x: x, y: size.height - rail + rail * 0.22, width: hole, height: hole),
                                 cornerSize: CGSize(width: 1, height: 1))
            x += hole * 2.6
        }
        ctx.fill(holes, with: .color(Track.chalk.opacity(0.10)))
    }

    /// The image itself.
    private func drawSmears(_ ctx: inout GraphicsContext, size: CGSize) {
        let rail = max(size.height * 0.045, 3)
        let top = rail * 1.6
        let usable = size.height - top * 2
        let laneCount = max(film.lanes.count, 1)
        let laneHeight = usable / CGFloat(laneCount)
        let columnWidth = size.width / CGFloat(columns)

        for (index, lane) in film.lanes.enumerated() {
            let yCentre = top + laneHeight * (CGFloat(index) + 0.5)
            // The user's smear is drawn taller and hotter. On a share card seen
            // at thumbnail size, you must be able to find yourself instantly.
            let bandHeight = laneHeight * (lane.isUser ? 0.82 : 0.62)

            for column in 0..<columns {
                let t = film.t0 + film.duration * (Double(column) + 0.5) / Double(columns)
                let value = film.intensity(lane.id, at: t)
                guard value > 0.012 else { continue }

                let x = CGFloat(column) * columnWidth
                // Vertical profile: a body is denser at its middle than at its
                // edges, so each column is a soft vertical gradient rather than
                // a flat bar.
                let rect = CGRect(x: x, y: yCentre - bandHeight / 2, width: columnWidth + 0.6, height: bandHeight)
                ctx.fill(Path(rect), with: .linearGradient(
                    Gradient(stops: [
                        .init(color: lane.color.opacity(0), location: 0),
                        .init(color: lane.color.opacity(value * 0.85), location: 0.5),
                        .init(color: lane.color.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: 0, y: rect.minY),
                    endPoint: CGPoint(x: 0, y: rect.maxY)
                ))

                // Hot core where the body was dead-centre in the slit.
                if value > 0.55 {
                    let coreH = bandHeight * 0.24
                    ctx.fill(
                        Path(CGRect(x: x, y: yCentre - coreH / 2, width: columnWidth + 0.6, height: coreH)),
                        with: .color(Track.chalk.opacity((value - 0.55) * 1.5 * (lane.isUser ? 0.9 : 0.55)))
                    )
                }
            }
        }
    }

    private func drawChrome(_ ctx: inout GraphicsContext, size: CGSize) {
        let rail = max(size.height * 0.045, 3)
        let top = rail * 1.6
        let usable = size.height - top * 2
        let laneCount = max(film.lanes.count, 1)
        let laneHeight = usable / CGFloat(laneCount)

        // Winner's timecode: the one vertical reference in the frame.
        //
        // Chalk, not signal. This strip sits directly under a headline that goes
        // yellow for a personal best, and a second yellow on the same screen
        // demotes both of them to decoration.
        if let winner = film.lanes.compactMap(\.crossedAt).min() {
            let x = CGFloat((winner - film.t0) / film.duration) * size.width
            var line = Path()
            line.move(to: CGPoint(x: x, y: rail))
            line.addLine(to: CGPoint(x: x, y: size.height - rail))
            ctx.stroke(line, with: .color(Track.chalk.opacity(0.5)),
                       style: .init(lineWidth: 1, dash: [3, 4]))
        }

        for (index, lane) in film.lanes.enumerated() {
            let yCentre = top + laneHeight * (CGFloat(index) + 0.5)

            var name = ctx.resolve(
                Text(lane.name)
                    .font(Bib.label(min(laneHeight * 0.34, 12)))
                    .foregroundStyle(lane.color.opacity(lane.isUser ? 1 : 0.75))
            )
            name.shading = .color(lane.color.opacity(lane.isUser ? 1 : 0.75))
            ctx.draw(name, at: CGPoint(x: 9, y: yCentre - laneHeight * 0.28), anchor: .leading)

            // Someone whose crossing fell outside the window gets an honest
            // marker at the edge with how far back they were, rather than being
            // quietly cropped out of the picture.
            if !lane.inWindow,
               let crossed = lane.crossedAt,
               let winner = film.lanes.compactMap(\.crossedAt).min(),
               crossed > film.t1 {
                let behind = crossed - winner
                var tag = ctx.resolve(
                    Text("+" + (behind < 60 ? String(format: "%.1fs", behind) : Fmt.clock(behind)))
                        .font(Bib.mono(min(laneHeight * 0.3, 11), weight: .bold))
                        .foregroundStyle(lane.color.opacity(0.8))
                )
                tag.shading = .color(lane.color.opacity(0.8))
                ctx.draw(tag, at: CGPoint(x: size.width - 8, y: yCentre), anchor: .trailing)
            }
        }

        // Timecode ruler along the bottom rail — tenths of a second.
        var ticks = Path()
        let tickCount = Int(film.duration * 10)
        if tickCount > 0, tickCount < 200 {
            for i in 0...tickCount {
                let x = size.width * CGFloat(Double(i) / (film.duration * 10))
                let tall = i % 10 == 0
                ticks.move(to: CGPoint(x: x, y: size.height - rail))
                ticks.addLine(to: CGPoint(x: x, y: size.height - rail - (tall ? 7 : 3)))
            }
            ctx.stroke(ticks, with: .color(Track.chalk.opacity(0.2)), lineWidth: 1)
        }
    }

    /// The develop wipe. Everything to the right of the wavefront is still film.
    private func drawUndeveloped(_ ctx: inout GraphicsContext, size: CGSize) {
        guard develop < 1 else { return }
        let edge = size.width * CGFloat(develop)
        ctx.fill(
            Path(CGRect(x: edge, y: 0, width: size.width - edge, height: size.height)),
            with: .color(Color(hex: 0x05070E))
        )
        // A bright wavefront, like the emulsion catching light as it comes up.
        ctx.fill(
            Path(CGRect(x: edge - 14, y: 0, width: 18, height: size.height)),
            with: .linearGradient(
                Gradient(colors: [Track.chalk.opacity(0), Track.chalk.opacity(0.22), Track.chalk.opacity(0)]),
                startPoint: CGPoint(x: edge - 14, y: 0), endPoint: CGPoint(x: edge + 4, y: 0)
            )
        )
    }

    /// A race with no usable finish data still has to say something.
    private func drawUnexposed(_ ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x05070E)))
        var text = ctx.resolve(
            Text("NO FINISH RECORDED")
                .font(Bib.label(min(size.height * 0.18, 12)))
                .foregroundStyle(Track.chalkFaint)
        )
        text.shading = .color(Track.chalkFaint)
        ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }

    private var accessibilitySummary: String {
        guard film.hasImage else { return "No finish recorded" }
        let names = film.lanes.map(\.name).joined(separator: ", then ")
        if let margin = film.winningMargin {
            return "Finish order: \(names). Won by \(String(format: "%.2f", margin)) seconds."
        }
        return "Finish order: \(names)."
    }
}
