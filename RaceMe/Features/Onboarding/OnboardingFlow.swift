import SwiftUI

/// Seventeen screens, long on purpose.
///
/// Every one either extracts something used later or invests the user further.
/// There is no filler, no account wall before the value moment, and no OS
/// permission prompt that hasn't been asked for in our own words first.
///
/// The order is the argument: hook → who are you → what do you want → here's
/// what we built for you → now go win one → *then* we talk about money.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case coldOpen      // S0
    case hook          // S1
    case identity      // S2
    case pace          // S3
    case goals         // S4
    case rival         // S5 (conditional)
    case frequency     // S6
    case timing        // S7
    case proof         // S8
    case driver        // S9
    case compute       // S10
    case card          // S11
    case permissions   // S12
    case handle        // S13
    case tasteRace     // S14
    case paywall       // S15

    var id: Int { rawValue }

    /// The progress rule runs S2 → S13 and nowhere else. Before S2 there's
    /// nothing to measure; after S13 they're in a race and a progress bar would
    /// be an insult.
    var showsProgress: Bool {
        (OnboardingStep.identity.rawValue...OnboardingStep.handle.rawValue).contains(rawValue)
    }

    var progress: Double? {
        guard showsProgress else { return nil }
        let first = Double(OnboardingStep.identity.rawValue)
        let last = Double(OnboardingStep.handle.rawValue)
        let n = (Double(rawValue) - first) / (last - first)
        // Starts at 15%, moves fast early and slows late. An exponent below 1
        // front-loads the movement, which is what makes the first three taps
        // feel like real progress.
        return 0.15 + 0.85 * pow(n, 0.62)
    }

    /// Back is available everywhere except the cold open and the taste race —
    /// you can't rewind out of a race that's already running.
    var allowsBack: Bool {
        switch self {
        case .coldOpen, .tasteRace: false
        default: true
        }
    }
}

@MainActor
@Observable
final class OnboardingModel {
    var step: OnboardingStep = .coldOpen
    var forward = true
    /// The result of the taste race — carried into the paywall, which shows it
    /// back to them as part of what's at stake.
    var tasteResult: RaceResult?
    /// Built for real on S10 and handed to Home, so the first screen after
    /// onboarding is already populated with a race chosen from their answers.
    var stagedRace: StagedRace?

    let profile: RunnerProfile
    let services: AppServices

    init(profile: RunnerProfile, services: AppServices) {
        self.profile = profile
        self.services = services
    }

    func advance() {
        forward = true
        var next = OnboardingStep(rawValue: step.rawValue + 1)
        // S5 only exists for people who said they're chasing a specific person.
        if next == .rival, !profile.goals.contains(.beatSomeone) {
            next = OnboardingStep(rawValue: OnboardingStep.rival.rawValue + 1)
        }
        guard let next else { return }
        withAnimation(Spring.navigate) { step = next }
    }

    func back() {
        forward = false
        var previous = OnboardingStep(rawValue: step.rawValue - 1)
        if previous == .rival, !profile.goals.contains(.beatSomeone) {
            previous = OnboardingStep(rawValue: OnboardingStep.rival.rawValue - 1)
        }
        guard let previous else { return }
        withAnimation(Spring.navigate) { step = previous }
    }

    /// The taste race: 400m against a ghost pitched a few percent slower than
    /// their stated pace, compressed so it plays out in roughly twenty-five
    /// seconds of real time. Full fidelity — the actual race screen, the actual
    /// lane, the actual haptics. They win, and they finish holding a photo finish.
    func makeTasteRace() -> RaceViewModel {
        let distance: Double = 400
        let userPace = profile.race5KPaceSecPerKm

        var ghost = Racer(
            handle: "pacer",
            displayName: profile.rivalMention ?? "The Pacer",
            mark: .blade,
            isUser: false,
            handicapPaceSecPerKm: userPace,
            colorIndex: 0
        )
        // A few percent slower. Enough that they win; close enough that it was
        // a race and not a walkover.
        ghost.handicapPaceSecPerKm = userPace * 1.035

        let config = RaceConfig(
            distanceMeters: distance,
            mode: .headToHead,
            scoring: .raw,
            participants: [profile.asRacer(), ghost]
        )

        let movement = SimulatedMovementSource(
            paceSecPerKm: userPace,
            shape: profile.archetype.paceShape,
            seed: 0x7A57E
        )

        let model = RaceViewModel(
            config: config, movement: movement, profile: profile, services: services, seed: 0x7A57E
        )
        // Compress a two-minute 400 into ~22 seconds of screen time. Because both
        // distance and elapsed scale together, pace and gap stay honest — only
        // the rate of change is heightened.
        let expected = userPace * distance / 1000
        model.timeScale = max(1, expected / 22)
        return model
    }
}

// MARK: - Container

struct OnboardingFlow: View {
    @State var model: OnboardingModel
    /// Hands over the race staged for real on S10, so Home opens on the thing
    /// the compute screen just claimed to be building rather than quietly
    /// rebuilding it.
    var onFinish: (StagedRace?) -> Void

    @Environment(\.motion) private var motion
    @Namespace private var glassNS

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                if model.step != .coldOpen && model.step != .tasteRace {
                    OnboardingChrome(
                        progress: model.step.progress,
                        canGoBack: model.step.allowsBack,
                        onBack: model.back
                    )
                    .padding(.top, 8)
                }

                ZStack {
                    screen
                        .id(model.step)
                        .transition(.onboardingStep(forward: model.forward, reduced: motion.reduced))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.glassNamespace, glassNS)
        .atmosphere(atmosphere)
        .task {
            Haptics.shared.prepare()
            // `-demoScreen paywall` etc. drops in at that step instead of
            // making you tap through everything ahead of it.
            if let target = DemoMode.screen?.onboardingStep {
                model.step = target
            }
        }
    }

    private var atmosphere: Atmosphere {
        switch model.step {
        case .card, .paywall: .leading
        case .tasteRace: .closing
        default: .idle
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.step {
        case .coldOpen:
            ColdOpenScreen(onStart: model.advance)
        case .hook:
            HookScreen(onDone: model.advance)
        case .identity:
            IdentityScreen(profile: model.profile, onPick: model.advance)
        case .pace:
            PaceScreen(profile: model.profile, onDone: model.advance)
        case .goals:
            GoalsScreen(profile: model.profile, onDone: model.advance)
        case .rival:
            RivalScreen(profile: model.profile, onDone: model.advance)
        case .frequency:
            FrequencyScreen(profile: model.profile, onPick: model.advance)
        case .timing:
            TimingScreen(profile: model.profile, onPick: model.advance)
        case .proof:
            ProofScreen(profile: model.profile, onDone: model.advance)
        case .driver:
            DriverScreen(profile: model.profile, onPick: model.advance)
        case .compute:
            ComputeScreen(model: model, onDone: model.advance)
        case .card:
            CardRevealScreen(profile: model.profile, onDone: model.advance)
        case .permissions:
            PermissionScreen(profile: model.profile, onDone: model.advance)
        case .handle:
            HandleScreen(profile: model.profile, onDone: model.advance)
        case .tasteRace:
            TasteRaceScreen(model: model)
        case .paywall:
            PaywallScreen(
                profile: model.profile,
                services: model.services,
                result: model.tasteResult,
                onFinish: {
                    model.profile.completedOnboarding = true
                    onFinish(model.stagedRace)
                }
            )
        }
    }
}
