import SwiftUI

/// S1. Three cards, each with a live-animating mock of real UI.
///
/// Not screenshots. A screenshot of a racing app is a still of the one thing
/// that's interesting *because* it moves. Each of these is the actual component
/// the product uses, driven by a small live simulation, so what they're being
/// promised and what they'll get are literally the same code.
struct HookScreen: View {
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @State private var index = 0
    @State private var advance: Task<Void, Never>?

    private let cards: [(title: String, sub: String)] = [
        ("Race anyone.\nRight now.", "Live, head to head, wherever you both are."),
        ("Or race the version of\nyou from last Tuesday.", "Your own past run, on the line beside you."),
        ("Then go take the\ntop of the board.", "Friends, global, and a league that resets every Monday."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            ZStack {
                mock
                    .id(index)
                    .transition(
                        motion.reduced
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                    )
            }
            .frame(height: 208)
            .padding(.horizontal, 20)

            Spacer(minLength: 26)

            VStack(alignment: .leading, spacing: 10) {
                Text(cards[index].title)
                    .font(Prose.title(34))
                    .foregroundStyle(Track.chalk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(cards[index].sub)
                    .font(Prose.copy(17))
                    .foregroundStyle(Track.chalkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .id("copy\(index)")
            .transition(motion.reduced ? .opacity : .opacity.combined(with: .offset(y: 10)))

            Spacer(minLength: 20)

            // Position dots. Three chalk ticks, not a page control.
            HStack(spacing: 6) {
                ForEach(0..<cards.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Track.you : Track.chalk.opacity(0.18))
                        .frame(width: i == index ? 22 : 8, height: 3)
                }
            }
            .animation(motion.animation(Spring.ui), value: index)

            Spacer(minLength: 24)

            GlassAction(title: index == cards.count - 1 ? "Let's go" : "Skip", morphID: GlassID.primaryAction) {
                advance?.cancel()
                onDone()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .contentShape(.rect)
        .onTapGesture { next() }
        .task { scheduleAdvance() }
        .onDisappear { advance?.cancel() }
    }

    @ViewBuilder
    private var mock: some View {
        switch index {
        case 0: LiveDuelMock()
        case 1: GhostMock()
        default: BoardMock()
        }
    }

    private func scheduleAdvance() {
        advance?.cancel()
        advance = Task { @MainActor in
            for _ in 0..<(cards.count - 1) {
                try? await Task.sleep(for: .milliseconds(2900))
                if Task.isCancelled { return }
                next(auto: true)
            }
        }
    }

    private func next(auto: Bool = false) {
        guard index < cards.count - 1 else {
            if !auto { onDone() }
            return
        }
        if !auto { Haptics.shared.play(.select) }
        withAnimation(motion.animation(Spring.navigate)) { index += 1 }
    }
}

// MARK: - Mocks
//
// Each one is a live simulation, not a canned loop, so it never plays the same
// beat twice — and it's built on the same components the real screens use.

/// Two runners trading a lead on a real mini-lane.
private struct LiveDuelMock: View {
    @State private var start = Date()

    var body: some View {
        MockFrame(label: "LIVE · 5K") {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                // A slow sinusoidal exchange with a second harmonic, so the lead
                // changes hands at irregular intervals rather than metronomically.
                let swap = sin(t * 0.62) * 7 + sin(t * 1.37) * 3
                VStack(spacing: 10) {
                    MiniLane(runners: [
                        .init(id: idA, color: Track.you, progress: min(0.05 + t * 0.052, 0.95),
                              gapToLeader: min(0, swap), isUser: true),
                        .init(id: idB, color: Track.them, progress: min(0.05 + t * 0.05, 0.95),
                              gapToLeader: min(0, -swap), isUser: false),
                    ])
                    .frame(height: 52)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.signedMeters(swap))
                            .font(Bib.numeral(46))
                            .bibTracking(46)
                            .foregroundStyle(swap >= 0 ? Track.you : Track.them)
                        Text("M")
                            .font(Bib.label(13))
                            .foregroundStyle(Track.chalkFaint)
                        Spacer()
                        Text(Fmt.clock(600 + t * 3))
                            .font(Bib.mono(17, weight: .bold))
                            .foregroundStyle(Track.chalkDim)
                    }
                }
            }
        }
    }

    private let idA = UUID(), idB = UUID()
}

/// You against your own past run.
private struct GhostMock: View {
    @State private var start = Date()

    var body: some View {
        MockFrame(label: "GHOST · LAST TUESDAY") {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                let gap = 4 + sin(t * 0.5) * 9
                VStack(spacing: 10) {
                    MiniLane(runners: [
                        .init(id: idA, color: Track.you, progress: min(0.08 + t * 0.05, 0.95),
                              gapToLeader: min(0, gap), isUser: true),
                        // A ghost is drawn cool but dimmer than a live opponent —
                        // it's you, so it doesn't get the full aqua.
                        .init(id: idB, color: Track.them.opacity(0.55), progress: min(0.08 + t * 0.049, 0.95),
                              gapToLeader: min(0, -gap), isUser: false),
                    ])
                    .frame(height: 52)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            TrackLabel("You, today", size: 10)
                            Text("4:41").font(Bib.numeral(28)).foregroundStyle(Track.you)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            TrackLabel("You, last Tuesday", size: 10)
                            Text("4:49").font(Bib.numeral(28)).foregroundStyle(Track.them.opacity(0.7))
                        }
                    }
                }
            }
        }
    }

    private let idA = UUID(), idB = UUID()
}

/// Rows reordering on a board.
private struct BoardMock: View {
    @State private var order = [0, 1, 2, 3]
    @State private var timer: Task<Void, Never>?
    @Environment(\.motion) private var motion

    /// A named type rather than a `(String, Int, Bool)` tuple.
    ///
    /// Subscripting an anonymous tuple array three times inside a view builder
    /// (`rows[row].0`, `.1`, `.2`) gave the type checker enough overloads to
    /// consider that it gave up: "unable to type-check this expression in
    /// reasonable time". Named fields and an extracted row view fix it, and read
    /// better anyway.
    private struct Standing: Identifiable {
        let id: Int
        let name: String
        let points: Int
        let isUser: Bool
    }

    private let rows: [Standing] = [
        Standing(id: 0, name: "Karim", points: 812, isUser: false),
        Standing(id: 1, name: "You", points: 806, isUser: true),
        Standing(id: 2, name: "Noor", points: 794, isUser: false),
        Standing(id: 3, name: "Tobi", points: 771, isUser: false),
    ]

    var body: some View {
        MockFrame(label: "WEEKLY LEAGUE · SILVER") {
            VStack(spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.element) { position, row in
                    standingRow(rows[row], position: position)
                }
            }
            .animation(motion.animation(Spring.reorder), value: order)
        }
        .task {
            timer = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1150))
                    guard !Task.isCancelled else { return }
                    // The user climbs. That's the promise being made.
                    if let i = order.firstIndex(of: 1), i > 0 {
                        order.swapAt(i, i - 1)
                    } else {
                        order = [0, 1, 2, 3]
                    }
                }
            }
        }
        .onDisappear { timer?.cancel() }
    }

    private func standingRow(_ standing: Standing, position: Int) -> some View {
        let promoting = position < 2
        return HStack(spacing: 10) {
            Text("\(position + 1)")
                .font(Bib.numeral(16))
                .foregroundStyle(promoting ? Track.you : Track.chalkFaint)
                .frame(width: 16, alignment: .leading)
            Text(standing.name)
                .font(Prose.caption(15))
                .foregroundStyle(standing.isUser ? Track.chalk : Track.chalkDim)
            Spacer()
            Text("\(standing.points)")
                .font(Bib.mono(14, weight: .bold))
                .foregroundStyle(standing.isUser ? Track.you : Track.chalkFaint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(standing.isUser ? Track.you.opacity(0.12) : Color.clear)
        }
    }
}

/// The device-ish frame the mocks sit in. Solid, not glass — glass on a mock of
/// glass is exactly the stacking the direction forbids.
private struct MockFrame<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackLabel(label, size: 10)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Track.elevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Track.hairline, lineWidth: 1)
                }
        }
    }
}
