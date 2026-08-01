import SwiftUI

// The single-question screens. Each one collects something that gets used by
// name later — there isn't a screen in here whose answer disappears.

// MARK: - S2 · Identity

/// Sets difficulty *and* the register every later line of copy is written in.
///
/// "I don't lose" is bait, and it's deliberate: competitive users pick it, feel
/// immediately understood, and the app talks to them differently for the rest of
/// their life in it.
struct IdentityScreen: View {
    let profile: RunnerProfile
    var onPick: () -> Void

    var body: some View {
        QuestionScreen(title: "Which one's you?") {
            ForEach(SelfImage.allCases) { option in
                OptionRow(label: option.label, selected: profile.selfImage == option) {
                    profile.selfImage = option
                    onPick()
                }
            }
        }
    }
}

// MARK: - S4 · Goals

/// Two maximum. A goal list where everything is checked tells us nothing, and
/// the cap forces a real answer.
struct GoalsScreen: View {
    let profile: RunnerProfile
    var onDone: () -> Void

    @Environment(\.motion) private var motion

    private var canContinue: Bool { !profile.goals.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            QuestionScreen(
                title: "What are you actually chasing?",
                subtitle: "Pick up to two."
            ) {
                ForEach(Goal.allCases) { goal in
                    OptionRow(label: goal.label, selected: profile.goals.contains(goal)) {
                        toggle(goal)
                    }
                }
            }

            // The only question screen with a continue button, because it's the
            // only one where a single tap isn't a complete answer.
            GlassAction(title: "Continue", morphID: nil) { onDone() }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .opacity(canContinue ? 1 : 0.35)
                .disabled(!canContinue)
                .animation(motion.animation(Spring.ui), value: canContinue)
        }
    }

    private func toggle(_ goal: Goal) {
        withAnimation(motion.animation(Spring.snap)) {
            if let i = profile.goals.firstIndex(of: goal) {
                profile.goals.remove(at: i)
            } else if profile.goals.count < 2 {
                profile.goals.append(goal)
            } else {
                // Replace the oldest rather than refusing the tap. A tap that
                // does nothing reads as a broken button.
                profile.goals.removeFirst()
                profile.goals.append(goal)
            }
        }
    }
}

// MARK: - S6 · Frequency

/// Framed as a commitment they're making, not a setting they're picking. The
/// difference is entirely in the copy and it's worth real completion.
struct FrequencyScreen: View {
    let profile: RunnerProfile
    var onPick: () -> Void

    var body: some View {
        QuestionScreen(
            title: "How often are you racing?",
            subtitle: "We'll hold you to it.",
            footnote: "You can change this any time. We won't nag you about it."
        ) {
            ForEach(RaceFrequency.allCases) { option in
                OptionRow(label: option.label, selected: profile.frequency == option) {
                    profile.frequency = option
                    onPick()
                }
            }
        }
    }
}

// MARK: - S7 · Timing

/// Telling people *why* you're asking lifts completion measurably, and costs one
/// line of type.
struct TimingScreen: View {
    let profile: RunnerProfile
    var onPick: () -> Void

    var body: some View {
        QuestionScreen(
            title: "When do you usually run?",
            footnote: "So we ping you before, not during."
        ) {
            ForEach(RunWindow.allCases) { option in
                OptionRow(label: option.label, detail: option.clock, selected: profile.window == option) {
                    profile.window = option
                    onPick()
                }
            }
        }
    }
}

// MARK: - S9 · Driver

/// Maps to which race modes surface first on Home, and to how the simulator
/// choreographs opponents against this user. Someone who's motivated by being
/// chased gets races where they lead and feel it evaporate.
struct DriverScreen: View {
    let profile: RunnerProfile
    var onPick: () -> Void

    var body: some View {
        QuestionScreen(
            title: "What actually makes you push?",
            footnote: "This decides what we put in front of you first."
        ) {
            ForEach(Driver.allCases) { option in
                OptionRow(label: option.label, selected: profile.driver == option) {
                    profile.driver = option
                    onPick()
                }
            }
        }
    }
}

// MARK: - S5 · The rival

/// One field. Worth more retention than any feature in this MVP.
///
/// The name goes into the home screen, the notifications, the league copy, and
/// the paywall. "We won't tell them" is doing the real work here — it removes
/// the only reason someone would hesitate.
struct RivalScreen: View {
    let profile: RunnerProfile
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @FocusState private var focused: Bool
    @State private var name: String = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 10) {
                Text("Who?")
                    .font(Prose.title(40))
                    .foregroundStyle(Track.chalk)
                Text("First name is enough.")
                    .font(Prose.copy(17))
                    .foregroundStyle(Track.chalkDim)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 26)

            // Huge, as specified. The field is the screen.
            TextField("", text: $name, prompt: Text("Name").foregroundStyle(Track.chalk.opacity(0.22)))
                .font(Bib.numeral(52))
                .bibTracking(52)
                .foregroundStyle(Track.you)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(commit)
                .padding(.horizontal, 24)

            Rectangle()
                .fill(trimmed.isEmpty ? Track.chalk.opacity(0.14) : Track.you)
                .frame(height: 2)
                .padding(.horizontal, 24)
                .animation(motion.animation(Spring.ui), value: trimmed.isEmpty)

            Text("We won't tell them.")
                .font(Prose.caption(15))
                .foregroundStyle(Track.chalkFaint)
                .padding(.horizontal, 24)
                .padding(.top, 14)

            Spacer(minLength: 24)

            HStack(spacing: 14) {
                // The skip stays plain and genuinely tappable. A greyed-out
                // escape hatch is the kind of thing that costs more in week two
                // than it wins in week one.
                QuietAction(title: "Skip") {
                    profile.rivalName = nil
                    onDone()
                }
                GlassAction(title: "Lock it in", morphID: nil, fullWidth: true) { commit() }
                    .opacity(trimmed.isEmpty ? 0.35 : 1)
                    .disabled(trimmed.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .animation(motion.animation(Spring.ui), value: trimmed.isEmpty)
        }
        .onAppear {
            name = profile.rivalName ?? ""
            // A beat before the keyboard, so the screen is legible first.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                focused = true
            }
        }
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        profile.rivalName = trimmed
        Haptics.shared.play(.commit)
        onDone()
    }
}
