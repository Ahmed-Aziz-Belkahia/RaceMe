import SwiftUI

/// S15. It lands after they've won, never before.
///
/// What's at stake is shown using their own data — their card, their handicap,
/// their photo finish, their rival's name. Nothing here is a generic feature
/// grid, because a feature grid is what you show someone who hasn't experienced
/// the product yet, and this person just did.
///
/// The free path stays visible, plain, and genuinely tappable. Dark patterns
/// cost more in retention than they win in conversion, and they get apps
/// rejected.
struct PaywallScreen: View {
    let profile: RunnerProfile
    let services: AppServices
    let result: RaceResult?
    var onFinish: () -> Void

    @Environment(\.motion) private var motion
    @State private var plans: [SubscriptionPlan] = []
    @State private var selected: String = "annual"
    @State private var purchasing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headline
                    stakes
                    planPicker
                    footer
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .atmosphere(.leading)
        .safeAreaInset(edge: .bottom) { commit }
        .task { plans = await services.subscriptions.plans() }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep your card.")
                .font(Bib.hero(64))
                .bibTracking(64)
                .foregroundStyle(Track.chalk)

            Text(pitch)
                .font(Prose.copy(18))
                .foregroundStyle(Track.chalkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .staggeredAppear(0, distance: 16)
    }

    /// Written from their answers. Their rival, their archetype, their handicap.
    private var pitch: String {
        let archetype = profile.archetype.name
        if let rival = profile.rivalMention {
            return "You're \(archetype). Your handicap is set, and you're four races from beating \(rival)'s pace. Free keeps one race a week — everything else stops here."
        }
        return "You're \(archetype). Your handicap is set and your card is live. Free keeps one race a week — everything else stops here."
    }

    // MARK: Stakes

    /// Their own artifacts, shown back to them. The card goes solid rather than
    /// glass here, because the plans below need the glass more.
    @MainActor private var stakes: some View {
        VStack(alignment: .leading, spacing: 14) {
            RacerCardView(profile: profile, sweep: false, compact: true, plain: true)

            if let result {
                VStack(alignment: .leading, spacing: 8) {
                    TrackLabel("Your first photo finish")
                    PhotoFinishView(film: PhotoFinishFilm.build(from: result), develop: 1)
                        .frame(height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .staggeredAppear(1, distance: 16)
    }

    // MARK: Plans

    /// Three plans in **one** glass container, so they merge and refract as a
    /// single piece of material rather than three separate panes floating on the
    /// page. That's what keeps the screen inside the two-glass-surface ceiling,
    /// and it's what the grouping behaviour is for.
    private var planPicker: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(plans) { plan in
                    PlanRow(plan: plan, selected: selected == plan.id) {
                        Haptics.shared.play(.select)
                        withAnimation(motion.animation(Spring.snap)) { selected = plan.id }
                    }
                }
            }
        }
        .staggeredAppear(2, distance: 16)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(Prose.caption(15))
                    .foregroundStyle(Track.signal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(termsLine)
                .font(Prose.caption(14))
                .foregroundStyle(Track.chalkFaint)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Button("Restore purchases") { restore() }
                Button("Terms") {}
                Button("Privacy") {}
            }
            .font(Prose.caption(14))
            .foregroundStyle(Track.chalkFaint)
            .buttonStyle(.pressable(scale: 0.98, haptic: nil))
        }
        .staggeredAppear(3, distance: 16)
    }

    private var termsLine: String {
        guard let plan = plans.first(where: { $0.id == selected }) else { return "" }
        if let trial = plan.trialDays {
            return "\(trial) days free, then \(plan.headlinePrice) a year. Cancel any time in Settings — we'll remind you two days before it charges."
        }
        return "\(plan.headlinePrice)\(plan.id == "lifetime" ? ", once." : " a month. Cancel any time in Settings.")"
    }

    // MARK: Commit

    private var commit: some View {
        VStack(spacing: 2) {
            GlassAction(
                title: purchasing ? "One second" : commitTitle,
                morphID: GlassID.primaryAction
            ) {
                purchase()
            }
            .disabled(purchasing)

            // Plain, legible, the same size as any other body copy on the
            // screen, and it does exactly what it says.
            QuietAction(title: "Continue with the free version") {
                onFinish()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .background {
            LinearGradient(
                colors: [Track.base.opacity(0), Track.base.opacity(0.9), Track.base],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var commitTitle: String {
        guard let plan = plans.first(where: { $0.id == selected }) else { return "Continue" }
        return plan.trialDays != nil ? "Start free trial" : "Get RaceMe"
    }

    private func purchase() {
        guard let plan = plans.first(where: { $0.id == selected }) else { return }
        purchasing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let ok = try await services.subscriptions.purchase(plan)
                purchasing = false
                if ok {
                    profile.isSubscribed = true
                    Haptics.shared.play(.win)
                    onFinish()
                } else {
                    errorMessage = RaceMeError.purchaseFailed.errorDescription
                }
            } catch {
                purchasing = false
                Haptics.shared.play(.reject)
                errorMessage = [
                    RaceMeError.purchaseFailed.errorDescription,
                    RaceMeError.purchaseFailed.recoverySuggestion,
                ].compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    private func restore() {
        Task { @MainActor in
            let restored = (try? await services.subscriptions.restore()) ?? false
            if restored {
                profile.isSubscribed = true
                Haptics.shared.play(.commit)
                onFinish()
            } else {
                Haptics.shared.play(.select)
                errorMessage = "No previous purchase on this Apple Account. If you bought it elsewhere, sign in with that account and try again."
            }
        }
    }
}

// MARK: - Plan row

private struct PlanRow: View {
    let plan: SubscriptionPlan
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Chalk ring rather than a system radio control.
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Track.you : Track.chalk.opacity(0.24), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if selected {
                        Circle().fill(Track.you).frame(width: 10, height: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(Prose.headline(18))
                            .foregroundStyle(Track.chalk)
                        if let trial = plan.trialDays {
                            // The only signal-yellow element on this screen.
                            Text("\(trial) DAYS FREE")
                                .font(Bib.label(10))
                                .labelTracking()
                                .foregroundStyle(Track.base)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Track.signal))
                        }
                    }
                    if let note = plan.perMonthNote {
                        Text(note)
                            .font(Prose.caption(14))
                            .foregroundStyle(Track.chalkFaint)
                    }
                }

                Spacer(minLength: 0)

                Text(plan.headlinePrice)
                    .font(Bib.numeral(24))
                    .bibTracking(24)
                    .foregroundStyle(selected ? Track.chalk : Track.chalkDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.pressable(scale: 0.985, haptic: nil))
        .glassEffect(
            selected ? .regular.tint(Track.you.opacity(0.28)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 18)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
