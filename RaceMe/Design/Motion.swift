import SwiftUI

/// Springs only. There is not one `.easeInOut` or raw duration in this app.
///
/// Parameters are expressed as Apple expresses them to designers — *response*
/// (how fast it reaches the target, in seconds) and *bounce* (0 = critically
/// damped, no overshoot). Bounce is only ever spent where the interaction
/// itself carried momentum: a flick, a throw, a celebration. A menu that merely
/// appeared has no business overshooting.
enum Spring {
    /// The house default. Critically damped, nothing distracting.
    static let ui = Animation.spring(duration: 0.34, bounce: 0)
    /// Selections, toggles, taps that commit. Snappier, still no overshoot.
    static let snap = Animation.spring(duration: 0.22, bounce: 0)
    /// Something the user threw, or that arrived under its own steam.
    static let momentum = Animation.spring(duration: 0.4, bounce: 0.18)
    /// Sheets and drawers.
    static let sheet = Animation.spring(duration: 0.3, bounce: 0.2)
    /// Leaderboard rows physically swapping places.
    static let reorder = Animation.spring(duration: 0.38, bounce: 0.22)
    /// Screen-to-screen hierarchical travel.
    static let navigate = Animation.spring(duration: 0.36, bounce: 0.05)
    /// The only place allowed past 400ms. Wins, PRs, promotions.
    static let celebrate = Animation.spring(duration: 0.62, bounce: 0.42)
    /// Live values easing to a new reading. Never snaps; a gap slides 8 → 12.
    static let liveValue = Animation.spring(duration: 0.5, bounce: 0)
    /// The ambient background. Long enough to be felt and not seen.
    static let ambient = Animation.spring(duration: 3.4, bounce: 0)
}

// MARK: - Reduce Motion

/// Reduce Motion is designed in from the start, not retrofitted. With it on:
/// travel becomes a cross-fade, celebration becomes a static badge, and the
/// ambient background freezes. Feedback does not disappear — it stops moving.
struct MotionPreference {
    let reduced: Bool

    func animation(_ spring: Animation) -> Animation {
        reduced ? .spring(duration: 0.2, bounce: 0) : spring
    }

    /// Travel vs. arrive.
    func transition(_ moving: AnyTransition) -> AnyTransition {
        reduced ? .opacity : moving
    }

    /// Scale factor for anything that translates across the screen.
    var travel: CGFloat { reduced ? 0 : 1 }
}

private struct MotionPreferenceKey: EnvironmentKey {
    static let defaultValue = MotionPreference(reduced: false)
}

extension EnvironmentValues {
    var motion: MotionPreference {
        get { self[MotionPreferenceKey.self] }
        set { self[MotionPreferenceKey.self] = newValue }
    }
}

/// Bridges the system setting into `\.motion` once, at the root, so no view
/// downstream has to remember to check two things.
struct MotionEnvironment: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.environment(\.motion, MotionPreference(reduced: reduceMotion))
    }
}

extension View {
    func providesMotionPreference() -> some View { modifier(MotionEnvironment()) }
}

// MARK: - Interpolated live values

/// A number that is never allowed to snap.
///
/// Live race values (gap, pace, distance) arrive from the engine at 30Hz in
/// discrete steps. Rendered raw they jitter. This carries a spring per value so
/// the display slides between readings, and — critically — it is *interruptible*:
/// a new target mid-flight retargets from the current on-screen value and
/// inherits its velocity rather than jumping.
@MainActor
@Observable
final class InterpolatedValue {
    private(set) var value: Double
    private var velocity: Double = 0
    private var target: Double

    /// Response in seconds. Critically damped — live numbers must never overshoot,
    /// or a gap of +12 briefly reads +14 and the user is being lied to.
    private let response: Double

    init(_ initial: Double = 0, response: Double = 0.32) {
        value = initial
        target = initial
        self.response = response
    }

    func retarget(_ newValue: Double) { target = newValue }

    /// Hard set — use on race start / reset, never during a race.
    func reset(to newValue: Double) {
        value = newValue
        target = newValue
        velocity = 0
    }

    /// Critically damped analytic spring step. Stable at any dt, which matters
    /// because this is driven off the display link and dt varies 8.3ms↔16.6ms
    /// as ProMotion changes rate.
    func step(dt: Double) {
        guard dt > 0 else { return }
        let omega = 2 * .pi / max(response, 0.0001)
        let dx = value - target
        let exp = Foundation.exp(-omega * dt)
        let newValue = target + (dx + (velocity + omega * dx) * dt) * exp
        let newVelocity = (velocity - (velocity + omega * dx) * omega * dt) * exp
        value = newValue
        velocity = newVelocity
    }
}

// MARK: - Staggered entrance

/// Light stagger, then stop. Six items is plenty — past that the last row is
/// waiting on choreography instead of being read.
struct StaggeredAppear: ViewModifier {
    let index: Int
    var maxStaggered: Int = 6
    var distance: CGFloat = 14
    @Environment(\.motion) private var motion
    @State private var shown = false

    private var delay: Double {
        motion.reduced ? 0 : Double(min(index, maxStaggered)) * 0.045
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : distance * motion.travel)
            .onAppear {
                withAnimation(motion.animation(Spring.ui).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int, maxStaggered: Int = 6, distance: CGFloat = 14) -> some View {
        modifier(StaggeredAppear(index: index, maxStaggered: maxStaggered, distance: distance))
    }
}

// MARK: - Press feedback

/// Feedback lands on touch-down, not on release. Waiting for touch-up to
/// acknowledge a tap is the single fastest way to make an interface feel dead.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.965
    var haptic: Haptic? = .select
    @Environment(\.motion) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(motion.animation(Spring.snap), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, let haptic { Haptics.shared.play(haptic) }
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(scale: CGFloat = 0.965, haptic: Haptic? = .select) -> PressableStyle {
        PressableStyle(scale: scale, haptic: haptic)
    }
}
