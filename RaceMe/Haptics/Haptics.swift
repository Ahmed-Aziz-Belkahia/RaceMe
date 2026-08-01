import CoreHaptics
import UIKit
import SwiftUI

/// The haptic vocabulary.
///
/// Haptics here are a language, not garnish. Every meaningful state change has a
/// word in this list, and each word means exactly one thing everywhere it is
/// used. Silence during a state change is a bug.
///
/// The grammar, roughly:
/// - **transients** = discrete events (a tap, a crossing, a commit)
/// - **continuous ramps** = something building or draining (a surge, a kick)
/// - **sharpness** carries urgency; **intensity** carries magnitude
/// - warm events (yours) are sharper and rise; cool events (theirs) are duller and fall
enum Haptic: Hashable, Sendable {
    // Interface
    /// Any answer tap, any option selection.
    case select
    /// A choice that changes state you can't casually undo. Heavier than select.
    case commit
    /// Navigating back, dismissing. Deliberately understated.
    case back
    /// Something is now invalid or unavailable.
    case reject

    // Countdown ritual
    /// 3 · 2 · 1 — pass 0, 1, 2 for rising sharpness.
    case countdownTick(Int)
    /// GO.
    case go

    // Race
    /// A kilometre (or mile) boundary crossed.
    case split
    /// **The signature.** Sharp transient into a short rising rumble.
    /// You just took the lead. This is the one haptic users will learn by feel.
    case leadTaken
    /// You just lost the lead. Dull transient into a falling rumble — the exact
    /// inverse, so the two are unmistakable through a jacket pocket.
    case leadLost
    /// A single beat of the final-200 heartbeat. `intensity` 0…1 rises to the line.
    case heartbeat(Double)
    /// A 🔥 arrived from a spectator. Light, quick, one flick — never enough to
    /// break stride.
    case reaction

    // Outcomes
    /// Heavy celebratory pattern. Wins, PRs, promotions.
    case win
    /// A single soft thud. Dignified. You lost; you were not punished.
    case loss
    /// New personal record — win, plus a bright signal transient on top.
    case record
    /// Weekly league promotion / relegation.
    case promote
    case relegate
}

@MainActor
final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Mirrors the system Haptics switch plus our own settings toggle.
    var enabled: Bool = true

    // Fallbacks for devices without the Taptic Engine's full pattern support.
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private var heartbeatTask: Task<Void, Never>?

    private init() {}

    // MARK: Lifecycle

    func prepare() {
        guard supportsHaptics, engine == nil else {
            lightImpact.prepare(); mediumImpact.prepare(); selection.prepare()
            return
        }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            // The engine dies on interruption (a call, Siri). Racers do not
            // restart the app to get their haptics back.
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.engine = nil }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
        lightImpact.prepare(); mediumImpact.prepare(); selection.prepare()
    }

    /// Wake the engine before a race so the first countdown tick isn't late.
    /// A haptic that lands 80ms after its visual is worse than no haptic.
    func warmUp() {
        prepare()
        try? engine?.start()
        heavyImpact.prepare()
        notification.prepare()
    }

    // MARK: Play

    func play(_ haptic: Haptic) {
        guard enabled else { return }
        guard let engine, supportsHaptics else { return fallback(haptic) }
        do {
            let pattern = try Self.pattern(for: haptic)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(haptic)
        }
    }

    // MARK: The final 200m heartbeat

    /// A rising heartbeat through the last 200m. Two-beat pattern (lub-dub),
    /// rate and intensity both climbing as the line approaches. It should feel
    /// like your own pulse being handed back to you slightly louder.
    func startHeartbeat(progress: @escaping @MainActor () -> Double) {
        guard enabled, heartbeatTask == nil else { return }
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let p = min(max(progress(), 0), 1)
                self.play(.heartbeat(p))
                // 100bpm → 176bpm across the final straight.
                let bpm = 100 + 76 * p
                let interval = 60.0 / bpm
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: Patterns

    private static func pattern(for haptic: Haptic) throws -> CHHapticPattern {
        switch haptic {
        case .select:
            return try CHHapticPattern(events: [transient(0, intensity: 0.42, sharpness: 0.62)], parameters: [])

        case .commit:
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.78, sharpness: 0.7),
                continuous(0.02, duration: 0.09, intensity: 0.34, sharpness: 0.3),
            ], parameters: [])

        case .back:
            return try CHHapticPattern(events: [transient(0, intensity: 0.28, sharpness: 0.24)], parameters: [])

        case .reject:
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.55, sharpness: 0.9),
                transient(0.09, intensity: 0.42, sharpness: 0.9),
            ], parameters: [])

        case .countdownTick(let i):
            // Each tick harder and brighter than the last. Anticipation is built
            // in the hand before it's built on screen.
            let step = Float(min(max(i, 0), 2))
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.5 + 0.16 * step, sharpness: 0.4 + 0.2 * step),
            ], parameters: [])

        case .go:
            return try CHHapticPattern(events: [
                transient(0, intensity: 1.0, sharpness: 1.0),
                continuous(0.01, duration: 0.16, intensity: 0.7, sharpness: 0.55),
            ], parameterCurves: [
                CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0.01, value: 1.0),
                    .init(relativeTime: 0.17, value: 0.0),
                ], relativeTime: 0),
            ])

        case .split:
            // Two clean ticks — a chip mat, twice.
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.62, sharpness: 0.85),
                transient(0.075, intensity: 0.45, sharpness: 0.85),
            ], parameters: [])

        case .leadTaken:
            // THE signature. Sharp transient, then a rumble that *rises* under it.
            return try CHHapticPattern(events: [
                transient(0, intensity: 1.0, sharpness: 0.95),
                continuous(0.03, duration: 0.34, intensity: 0.55, sharpness: 0.25),
            ], parameterCurves: [
                CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0.03, value: 0.18),
                    .init(relativeTime: 0.30, value: 1.0),
                    .init(relativeTime: 0.37, value: 0.0),
                ], relativeTime: 0),
                CHHapticParameterCurve(parameterID: .hapticSharpnessControl, controlPoints: [
                    .init(relativeTime: 0.03, value: 0.1),
                    .init(relativeTime: 0.37, value: 0.75),
                ], relativeTime: 0),
            ])

        case .leadLost:
            // The exact inverse: dull first, falling away. Reads as loss without
            // reading as punishment.
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.62, sharpness: 0.12),
                continuous(0.02, duration: 0.3, intensity: 0.45, sharpness: 0.1),
            ], parameterCurves: [
                CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0.02, value: 0.85),
                    .init(relativeTime: 0.32, value: 0.0),
                ], relativeTime: 0),
            ])

        case .heartbeat(let p):
            let rise = Float(min(max(p, 0), 1))
            let base = 0.35 + 0.5 * rise
            return try CHHapticPattern(events: [
                transient(0, intensity: base, sharpness: 0.18 + 0.2 * rise),
                transient(0.13, intensity: base * 0.66, sharpness: 0.14 + 0.16 * rise),
            ], parameters: [])

        case .reaction:
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.34, sharpness: 0.95),
            ], parameters: [])

        case .win:
            // Heavy, and it lands like something arriving rather than a chime.
            // Three accelerating strikes into a body-weight rumble.
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.85, sharpness: 0.6),
                transient(0.1, intensity: 0.92, sharpness: 0.7),
                transient(0.18, intensity: 1.0, sharpness: 0.85),
                continuous(0.2, duration: 0.55, intensity: 0.8, sharpness: 0.35),
            ], parameterCurves: [
                CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0.20, value: 1.0),
                    .init(relativeTime: 0.42, value: 0.62),
                    .init(relativeTime: 0.75, value: 0.0),
                ], relativeTime: 0),
            ])

        case .record:
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.85, sharpness: 0.6),
                transient(0.1, intensity: 0.92, sharpness: 0.7),
                transient(0.18, intensity: 1.0, sharpness: 0.9),
                continuous(0.2, duration: 0.6, intensity: 0.85, sharpness: 0.45),
                transient(0.62, intensity: 1.0, sharpness: 1.0),
            ], parameterCurves: [
                CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0.20, value: 1.0),
                    .init(relativeTime: 0.55, value: 0.5),
                    .init(relativeTime: 0.80, value: 0.0),
                ], relativeTime: 0),
            ])

        case .loss:
            // One soft thud. That's the whole thing. Losing gets acknowledged,
            // not scolded.
            return try CHHapticPattern(events: [
                continuous(0, duration: 0.22, intensity: 0.5, sharpness: 0.05),
            ], parameterCurves: [
                CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0, value: 0.75),
                    .init(relativeTime: 0.22, value: 0.0),
                ], relativeTime: 0),
            ])

        case .promote:
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.7, sharpness: 0.5),
                transient(0.09, intensity: 0.85, sharpness: 0.72),
                transient(0.17, intensity: 1.0, sharpness: 0.95),
            ], parameters: [])

        case .relegate:
            return try CHHapticPattern(events: [
                transient(0, intensity: 0.6, sharpness: 0.3),
                transient(0.11, intensity: 0.45, sharpness: 0.2),
                transient(0.24, intensity: 0.3, sharpness: 0.1),
            ], parameters: [])
        }
    }

    private static func transient(_ t: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: intensity),
            .init(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t)
    }

    private static func continuous(_ t: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: intensity),
            .init(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t, duration: duration)
    }

    // MARK: Fallback

    /// Older hardware, or CoreHaptics unavailable. Coarser, but never silent.
    private func fallback(_ haptic: Haptic) {
        switch haptic {
        case .select, .reaction, .back: selection.selectionChanged()
        case .commit, .split: mediumImpact.impactOccurred()
        case .countdownTick(let i): mediumImpact.impactOccurred(intensity: 0.5 + 0.2 * CGFloat(i))
        case .go, .leadTaken: heavyImpact.impactOccurred()
        case .leadLost: mediumImpact.impactOccurred(intensity: 0.5)
        case .heartbeat(let p): mediumImpact.impactOccurred(intensity: 0.4 + 0.5 * CGFloat(p))
        case .win, .record, .promote: notification.notificationOccurred(.success)
        case .loss, .relegate: mediumImpact.impactOccurred(intensity: 0.45)
        case .reject: notification.notificationOccurred(.warning)
        }
    }
}

// MARK: - Ergonomics

extension View {
    /// Fire a haptic when a value changes. Keeps the haptic on the same frame as
    /// the state change that caused it — causality and harmony, per the rule that
    /// visual and haptic must not drift apart.
    func haptic<V: Equatable>(_ haptic: Haptic, on value: V) -> some View {
        onChange(of: value) { _, _ in Haptics.shared.play(haptic) }
    }
}
