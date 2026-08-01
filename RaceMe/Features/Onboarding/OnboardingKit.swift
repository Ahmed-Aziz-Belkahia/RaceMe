import SwiftUI

/// Shared furniture for the seventeen screens.
///
/// The rules these enforce, so no individual screen has to remember them:
/// one question per screen, four options maximum, never scrolling, tapping an
/// answer advances, back is always there and always quiet, and every selection
/// gets a haptic.

// MARK: - Chrome

/// Progress runs S2 → S13 only. It starts at 15% rather than zero — a bar that
/// starts empty tells someone they've done nothing, which is the wrong thing to
/// say to a person who just tapped Start. It moves fast early and slows late,
/// because the early screens are cheap and the late ones need to feel close to
/// the end.
struct OnboardingChrome: View {
    let progress: Double?
    let canGoBack: Bool
    let onBack: () -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        HStack(spacing: 14) {
            // Low emphasis on purpose. Anxiety kills funnels, and a prominent
            // back button reads as "this is reversible", which it is.
            Button(action: {
                Haptics.shared.play(.back)
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Track.chalkFaint)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.pressable(scale: 0.9, haptic: nil))
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)
            .accessibilityLabel("Back")

            if let progress {
                // A chalk lane line that fills. Not a stock progress view.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Track.chalk.opacity(0.10))
                        Capsule()
                            .fill(Track.you)
                            .frame(width: max(geo.size.width * progress, 10))
                    }
                }
                .frame(height: 3)
                .animation(motion.animation(Spring.ui), value: progress)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("\(Int(progress * 100)) percent")
            } else {
                Spacer()
            }

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Question layout

/// The shape every question screen takes. Title top, options bottom, nothing in
/// between fighting for attention, and a fixed layout that cannot scroll.
struct QuestionScreen<Options: View>: View {
    let title: String
    var subtitle: String?
    /// Quiet line under the options — usually the reason we're asking, which
    /// measurably lifts completion.
    var footnote: String?
    @ViewBuilder var options: Options

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Body.title(34))
                    .foregroundStyle(Track.chalk)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(Body.copy(17))
                        .foregroundStyle(Track.chalkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 28)

            VStack(spacing: 10) { options }
                .padding(.horizontal, 20)

            if let footnote {
                Text(footnote)
                    .font(Body.caption(15))
                    .foregroundStyle(Track.chalkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
            }

            Spacer(minLength: 28)
        }
    }
}

/// One answer. Tapping it *is* the Next button — there is no Next button on any
/// question screen in this flow.
struct OptionRow: View {
    let label: String
    var detail: String?
    var selected: Bool = false
    let action: () -> Void

    @Environment(\.motion) private var motion
    @State private var flash = false

    var body: some View {
        Button {
            Haptics.shared.play(.select)
            // A rust wash confirms the tap landed *before* the screen leaves.
            //
            // Advancing in the same frame made this invisible — the answer you
            // chose was gone before it lit up, so seventeen screens in a row felt
            // like jump cuts with no acknowledgement. Ninety milliseconds is
            // under the threshold where a delay reads as lag and over the one
            // where the confirmation is perceptible.
            withAnimation(motion.animation(Spring.snap)) { flash = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                action()
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(Body.copy(19))
                        .foregroundStyle(Track.chalk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(Body.caption(15))
                            .foregroundStyle(Track.chalkFaint)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Track.you)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 64)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected || flash ? Track.you.opacity(0.16) : Track.elevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                selected || flash ? Track.you.opacity(0.6) : Track.hairline,
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.pressable(scale: 0.985, haptic: nil))
        .animation(motion.animation(Spring.snap), value: selected)
    }
}

// MARK: - Step transitions

/// Screens travel sideways, and back travels the other way. Enter and exit share
/// a path — a screen that arrives from the right and leaves through the bottom
/// makes the flow feel like it has no shape.
extension AnyTransition {
    static func onboardingStep(forward: Bool, reduced: Bool) -> AnyTransition {
        guard !reduced else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

// MARK: - Counting numeral

/// A number that counts up to its value, used on the proof screen and the
/// Racer Card. Driven by a spring, not a timer, so it decelerates into place
/// instead of stopping dead.
struct CountingNumber: View {
    let value: Double
    var format: (Double) -> String = { String(Int($0)) }
    var font: Font = Bib.hero(96)
    var color: Color = Track.chalk
    /// Delay before it starts, so several can be staggered.
    var delay: Double = 0

    @Environment(\.motion) private var motion
    @State private var shown: Double = 0

    var body: some View {
        Text(format(shown))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: shown))
            .onAppear {
                guard !motion.reduced else { shown = value; return }
                withAnimation(.spring(duration: 1.1, bounce: 0).delay(delay)) { shown = value }
            }
            .onChange(of: value) { _, new in
                withAnimation(motion.animation(Spring.liveValue)) { shown = new }
            }
            .accessibilityLabel(format(value))
    }
}
