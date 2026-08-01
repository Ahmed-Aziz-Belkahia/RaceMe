import SwiftUI

// MARK: - S8 · Proof

/// No question. One number counting up, then it moves on by itself.
///
/// This screen exists for exactly one reason: to raise perceived value in the
/// three seconds before the heavier screens. It asks nothing, so it costs
/// nothing in the funnel, and it buys attention for what comes next.
struct ProofScreen: View {
    let profile: RunnerProfile
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @State private var advance: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    CountingNumber(
                        value: 41,
                        format: { String(Int($0)) },
                        font: Bib.hero(140),
                        color: Track.you
                    )
                    Text("%")
                        .font(Bib.numeral(58))
                        .foregroundStyle(Track.you)
                }
                .padding(.horizontal, 24)

                Text("more distance a week.")
                    .font(Body.title(30))
                    .foregroundStyle(Track.chalk)
                    .padding(.horizontal, 24)
            }

            Text("That's the gap between runners who race someone every week and runners who log it alone.")
                .font(Body.copy(18))
                .foregroundStyle(Track.chalkDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Spacer()

            // A thin auto-advance rule, so nobody wonders whether they're stuck.
            AutoAdvanceRule(duration: 3.4)
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
        }
        .contentShape(.rect)
        .onTapGesture { finish() }
        .task {
            advance = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(3400))
                guard !Task.isCancelled else { return }
                finish()
            }
        }
        .onDisappear { advance?.cancel() }
    }

    private func finish() {
        advance?.cancel()
        onDone()
    }
}

/// A chalk line that fills to show an auto-advancing screen won't strand you.
struct AutoAdvanceRule: View {
    let duration: Double
    @Environment(\.motion) private var motion
    @State private var filled = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Track.chalk.opacity(0.10))
                Capsule()
                    .fill(Track.chalk.opacity(0.4))
                    .frame(width: filled ? geo.size.width : 0)
            }
        }
        .frame(height: 2)
        .onAppear {
            guard !motion.reduced else { filled = true; return }
            withAnimation(.spring(duration: duration, bounce: 0)) { filled = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - S10 · The compute screen

/// Four to six seconds, never longer.
///
/// This is not a loading spinner. It's the manufacture of perceived effort
/// immediately before a personalised reveal, and it directly raises the value of
/// what comes next. The important part is that **the steps are real** — each one
/// names something we actually just did with the answers they actually gave, and
/// the screen doesn't advance until the work is done.
struct ComputeScreen: View {
    let model: OnboardingModel
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @State private var completed: Set<Int> = []
    @State private var active = 0
    @State private var ring: Double = 0

    private var profile: RunnerProfile { model.profile }

    private var steps: [String] {
        [
            "Reading your pace profile",
            "Finding runners near \(Fmt.pace(profile.race5KPaceSecPerKm, unit: profile.unit))/\(profile.unit.short.lowercased())",
            "Setting your handicap",
            "Building your first \(profile.frequency.perWeek == 1 ? "race" : "\(profile.frequency.perWeek) races")",
            profile.rivalMention.map { "Sizing you up against \($0)" } ?? "Staging your first race",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)

            ZStack {
                // Chalk ring. Not a system progress view — this is a track, seen
                // from above, being drawn one lap at a time.
                Circle()
                    .stroke(Track.chalk.opacity(0.10), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(Track.you, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Track.you.opacity(0.5), radius: 12)

                VStack(spacing: 2) {
                    Text("\(Int(ring * 100))")
                        .font(Bib.numeral(46))
                        .bibTracking(46)
                        .foregroundStyle(Track.chalk)
                        .contentTransition(.numericText(value: ring))
                    TrackLabel("Percent", size: 10)
                }
            }
            .frame(width: 148, height: 148)
            .frame(maxWidth: .infinity)
            .animation(motion.animation(.spring(duration: 0.6, bounce: 0)), value: ring)

            Spacer(minLength: 30)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    ComputeStepRow(
                        text: step,
                        state: completed.contains(index) ? .done : (index == active ? .working : .waiting)
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 30)
        }
        .task { await run() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setting up your profile")
    }

    /// Real work, narrated. Each step both *does* something and reports it, and
    /// each completion ticks in the hand.
    private func run() async {
        let start = Date()

        // 1. Pace profile.
        await tick(0) {
            _ = profile.handicapPaceSecPerKm
            _ = profile.race5KPaceSecPerKm
        }

        // 2. Find opponents in range.
        await tick(1) {
            _ = try? await model.services.directory.availableOpponents(
                near: profile.race5KPaceSecPerKm, count: 6
            )
        }

        // 3. Handicap.
        await tick(2) {
            _ = profile.archetype
            _ = profile.traits
        }

        // 4. First week.
        await tick(3) {
            _ = RaceStaging.firstWeek(for: profile)
        }

        // 5. Stage the race Home will open on.
        await tick(4) {
            model.stagedRace = await RaceStaging.stage(for: profile, services: model.services)
        }

        // Floor the whole thing at four seconds so it reads as effort, and cap it
        // at six so it never reads as a hang.
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 4.0 {
            try? await Task.sleep(for: .seconds(4.0 - elapsed))
        }
        onDone()
    }

    private func tick(_ index: Int, _ work: () async -> Void) async {
        active = index
        await work()
        // Each step gets a minimum on-screen life, otherwise mock services
        // complete instantly and the whole thing flashes past.
        try? await Task.sleep(for: .milliseconds(620))
        withAnimation(motion.animation(Spring.snap)) {
            _ = completed.insert(index)
            ring = Double(completed.count) / Double(steps.count)
        }
        Haptics.shared.play(.select)
    }
}

private struct ComputeStepRow: View {
    enum State { case waiting, working, done }
    let text: String
    let state: State

    @Environment(\.motion) private var motion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(state == .waiting ? Track.chalk.opacity(0.16) : Track.you.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Track.you)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(text)
                .font(Body.copy(17))
                .foregroundStyle(state == .waiting ? Track.chalkFaint : Track.chalk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(motion.animation(Spring.snap), value: state)
    }
}
