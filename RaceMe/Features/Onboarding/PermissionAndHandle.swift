import SwiftUI
import UserNotifications
import CoreLocation

// MARK: - S12 · Permission priming

/// A custom screen before the system dialog, never a cold prompt.
///
/// The OS prompt is one-shot: say no once and the only way back is Settings,
/// which nobody visits. Priming roughly doubles opt-in and costs one screen —
/// and the promise it makes ("nothing else") has to be one the app actually
/// keeps, or it's just a slower way to lose trust.
///
/// The same pattern runs before the location prompt on the next panel.
struct PermissionScreen: View {
    let profile: RunnerProfile
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @State private var stage: Stage = .notifications

    private enum Stage { case notifications, location }

    var body: some View {
        Group {
            switch stage {
            case .notifications: notifications
            case .location: location
            }
        }
        .transition(motion.reduced ? .opacity : .move(edge: .trailing).combined(with: .opacity))
        .animation(motion.animation(Spring.navigate), value: stage)
    }

    // MARK: Notifications

    private var notifications: some View {
        PrimingLayout(
            title: "Two kinds of notifications.\nThat's it.",
            items: [
                ("bolt.fill", "Someone challenges you", "You'll want to know about this one."),
                ("clock.fill", "Twenty minutes before your usual run", profile.window.clock),
            ],
            promise: "Nothing else. No streaks nagging you, no marketing.",
            affirm: "Turn them on",
            decline: "Not now",
            onAffirm: {
                profile.notificationsAsked = true
                Task {
                    // Only now does the OS prompt fire. If they'd said no above,
                    // it never fires at all — which keeps the option alive.
                    let granted = (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                    await MainActor.run {
                        profile.notificationsGranted = granted
                        // The promise made two lines up the screen, kept
                        // immediately: their run window becomes the reminder
                        // time, and nothing else ever gets scheduled.
                        Notifications.scheduleRunReminders(for: profile)
                        withAnimation(Spring.navigate) { stage = .location }
                    }
                }
            },
            onDecline: {
                profile.notificationsAsked = true
                profile.notificationsGranted = false
                withAnimation(Spring.navigate) { stage = .location }
            }
        )
    }

    // MARK: Location

    private var location: some View {
        PrimingLayout(
            title: "We need location\nto measure a race.",
            items: [
                ("location.fill", "Only while you're racing", "We stop the moment you cross the line."),
                ("eye.slash.fill", "Your route stays on your phone", "We use distance and pace. Not where you live."),
            ],
            promise: "Without it we can't tell who's winning, and neither can you.",
            affirm: "Allow location",
            decline: "Later",
            onAffirm: {
                profile.locationAsked = true
                LocationPrimer.shared.request { granted in
                    profile.locationGranted = granted
                    onDone()
                }
            },
            onDecline: {
                profile.locationAsked = true
                profile.locationGranted = false
                onDone()
            }
        )
    }
}

/// Shared layout for both priming panels.
private struct PrimingLayout: View {
    let title: String
    let items: [(String, String, String)]
    let promise: String
    let affirm: String
    let decline: String
    let onAffirm: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)

            Text(title)
                .font(Body.title(32))
                .foregroundStyle(Track.chalk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Spacer(minLength: 30)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.0)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Track.you)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.1)
                                .font(Body.copy(18))
                                .foregroundStyle(Track.chalk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.2)
                                .font(Body.caption(15))
                                .foregroundStyle(Track.chalkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .staggeredAppear(index)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 22)

            Text(promise)
                .font(Body.caption(15))
                .foregroundStyle(Track.chalkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Spacer(minLength: 26)

            VStack(spacing: 4) {
                GlassAction(title: affirm, morphID: nil, action: onAffirm)
                // Always plain, always tappable, never greyed out.
                QuietAction(title: decline, action: onDecline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

/// Thin wrapper so the priming screen can fire the location prompt and get a
/// callback, without a whole location stack living in a view.
final class LocationPrimer: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPrimer()
    private let manager = CLLocationManager()
    private var completion: ((Bool) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request(_ completion: @escaping (Bool) -> Void) {
        switch manager.authorizationStatus {
        case .notDetermined:
            self.completion = completion
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            completion(true)
        default:
            completion(false)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let granted = manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse
        completion?(granted)
        completion = nil
    }
}

// MARK: - S13 · Identity

/// Handle and avatar. Six tap-to-cycle geometric presets in the user's colour,
/// not a photo upload — zero friction, real ownership. Asking a runner for a
/// photo of themselves at this point in the flow is asking them to leave.
struct HandleScreen: View {
    let profile: RunnerProfile
    var onDone: () -> Void

    @Environment(\.motion) private var motion
    @FocusState private var focused: Bool
    @State private var handle: String = ""
    @State private var mark: AvatarMark = .chevron

    private var cleaned: String {
        handle
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
    }

    private var valid: Bool { cleaned.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("What do we call you?")
                    .font(Body.title(32))
                    .foregroundStyle(Track.chalk)
                Text("This is the name on the board.")
                    .font(Body.copy(17))
                    .foregroundStyle(Track.chalkDim)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 26)

            // Six marks in the user's own colour. Tap to cycle.
            HStack(spacing: 10) {
                ForEach(AvatarMark.allCases) { option in
                    Button {
                        Haptics.shared.play(.select)
                        withAnimation(motion.animation(Spring.snap)) { mark = option }
                    } label: {
                        AvatarView(mark: option, color: Track.you, size: 46, emphasized: mark == option)
                            .opacity(mark == option ? 1 : 0.42)
                            .scaleEffect(mark == option ? 1 : 0.9)
                    }
                    .buttonStyle(.pressable(scale: 0.88, haptic: nil))
                    .accessibilityLabel("Avatar style \(option.rawValue + 1)")
                    .accessibilityAddTraits(mark == option ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 26)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("@")
                    .font(Bib.numeral(38))
                    .foregroundStyle(Track.chalkFaint)
                TextField("", text: $handle, prompt: Text("handle").foregroundStyle(Track.chalk.opacity(0.2)))
                    .font(Bib.numeral(38))
                    .bibTracking(38)
                    .foregroundStyle(Track.chalk)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(commit)
            }
            .padding(.horizontal, 24)

            Rectangle()
                .fill(valid ? Track.you : Track.chalk.opacity(0.14))
                .frame(height: 2)
                .padding(.horizontal, 24)
                .animation(motion.animation(Spring.ui), value: valid)

            Spacer(minLength: 24)

            GlassAction(title: "That's me", morphID: nil) { commit() }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .opacity(valid ? 1 : 0.35)
                .disabled(!valid)
                .animation(motion.animation(Spring.ui), value: valid)
        }
        .onAppear {
            handle = profile.handle
            mark = profile.mark
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                focused = true
            }
        }
    }

    private func commit() {
        guard valid else { return }
        profile.handle = cleaned
        profile.mark = mark
        Haptics.shared.play(.commit)
        onDone()
    }
}
