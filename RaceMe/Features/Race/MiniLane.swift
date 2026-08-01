import SwiftUI

/// The lane, shrunk.
///
/// Used by the Live now strip, the Home hero card, and the onboarding hook —
/// anywhere a race needs to be recognisable at a glance without being readable
/// in detail. Same visual language as the full lane so the small version reads
/// as a preview of the real thing rather than a different picture.
struct MiniLane: View {
    struct Runner: Identifiable, Equatable {
        let id: UUID
        let color: Color
        /// 0…1 through the race.
        let progress: Double
        /// Metres relative to the leader, negative behind. Drives the compressed
        /// spacing, so a close race looks close.
        let gapToLeader: Double
        let isUser: Bool
    }

    let runners: [Runner]
    var showsFinish: Bool = true
    var laneLines: Bool = true

    private let knee: Double = 4

    var body: some View {
        Canvas(opaque: false, colorMode: .extendedLinear) { ctx, size in
            guard !runners.isEmpty else { return }
            let laneCount = max(runners.count, 2)
            let laneHeight = size.height / CGFloat(laneCount)

            if laneLines {
                var lines = Path()
                for i in 0...laneCount {
                    let y = laneHeight * CGFloat(i)
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(lines, with: .color(Track.chalk.opacity(0.09)), lineWidth: 0.5)
            }

            let leadProgress = runners.map(\.progress).max() ?? 0
            let leadX = size.width * (0.12 + 0.66 * CGFloat(leadProgress))

            if showsFinish {
                let finishX = size.width * 0.88
                var line = Path()
                line.move(to: CGPoint(x: finishX, y: 0))
                line.addLine(to: CGPoint(x: finishX, y: size.height))
                ctx.stroke(line, with: .color(Track.chalk.opacity(0.3)),
                           style: .init(lineWidth: 1, dash: [2, 2]))
            }

            for (index, runner) in runners.enumerated() {
                let y = size.height - laneHeight * (CGFloat(index) + 0.5)
                // Same asinh compression as the full lane, at a smaller scale —
                // so a two-metre gap is still visible in a 44-point-tall card.
                let offset = CGFloat(asinh(abs(runner.gapToLeader) / knee)) * 7
                let x = max(6, leadX - (runner.gapToLeader < 0 ? offset : 0))

                // Trail
                var trail = Path()
                trail.move(to: CGPoint(x: max(2, x - 26), y: y))
                trail.addLine(to: CGPoint(x: x, y: y))
                ctx.stroke(trail, with: .linearGradient(
                    Gradient(colors: [runner.color.opacity(0), runner.color.opacity(0.55)]),
                    startPoint: CGPoint(x: x - 26, y: y), endPoint: CGPoint(x: x, y: y)
                ), style: .init(lineWidth: runner.isUser ? 2.5 : 2, lineCap: .round))

                let r: CGFloat = runner.isUser ? 3.6 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 2.4, y: y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                         with: .color(runner.color.opacity(0.2)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(runner.color))
            }
        }
        .accessibilityHidden(true)
    }

    /// Build from a live engine, read at draw time.
    ///
    /// Straight off the engine rather than out of a published snapshot, so a
    /// card can animate at its own rate without the whole strip re-laying out
    /// every time a position changes.
    static func runners(from engine: RaceEngine) -> [Runner] {
        let states = engine.config.participants.map { ($0, engine.state($0.id)) }
        let leader = states.map(\.1.scoredPosition).max() ?? 0
        return states.map { racer, state in
            Runner(
                id: racer.id,
                color: racer.color,
                progress: state.distance / engine.distanceMeters,
                gapToLeader: state.scoredPosition - leader,
                isUser: racer.isUser
            )
        }
    }

    /// Fallback for a race whose engine has already been retired — draws the
    /// last snapshot rather than an empty card.
    static func runners(from race: LiveRace) -> [Runner] {
        let leader = race.snapshot.states.values.map(\.scoredPosition).max() ?? 0
        return race.config.participants.map { racer in
            let state = race.snapshot.states[racer.id]
            return Runner(
                id: racer.id,
                color: racer.color,
                progress: (state?.distance ?? 0) / race.config.distanceMeters,
                gapToLeader: (state?.scoredPosition ?? 0) - leader,
                isUser: racer.isUser
            )
        }
    }
}
