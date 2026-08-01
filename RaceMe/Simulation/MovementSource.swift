import Foundation
import CoreLocation

/// Where the user's own distance and speed come from.
///
/// Two implementations ship: real GPS, and a simulator. The simulator isn't a
/// stub — it's how the entire product gets demoed at a desk, which you need
/// constantly when the hero screen is a live race.
protocol MovementSource: AnyObject {
    /// Metres covered since `start()`.
    var distance: Double { get }
    /// Current speed in m/s.
    var speed: Double { get }
    /// Whether the source currently believes its readings.
    var isReliable: Bool { get }
    /// Nil unless something is wrong, in which case it says what happened and
    /// what to do about it — never a bare apology.
    var fault: MovementFault? { get }

    func start()
    func stop()
    /// Advance by `dt`. Simulated sources integrate here; GPS sources ignore it.
    func tick(dt: Double, raceProgress: Double)
}

struct MovementFault: Equatable, Sendable {
    let headline: String
    let recovery: String

    static let noPermission = MovementFault(
        headline: "Location is off, so we can't measure your run.",
        recovery: "Turn it on in Settings and the race picks up where you are."
    )
    static let weakSignal = MovementFault(
        headline: "GPS signal is thin here.",
        recovery: "Your pace is estimated from motion until it comes back."
    )
}

// MARK: - Simulated movement (dev build + taste race)

/// Runs the user at a target pace with believable variation, so the whole app is
/// demoable without leaving the room.
///
/// Also powers the S14 taste race, where the user's "run" has to be convincing
/// enough that twenty-five seconds of it sells the product.
final class SimulatedMovementSource: MovementSource {
    private(set) var distance: Double = 0
    private(set) var speed: Double = 0
    var isReliable: Bool { true }
    var fault: MovementFault? { nil }

    /// Seconds per km the simulated user holds.
    var targetPaceSecPerKm: Double
    /// Pace shape applied across the race, so the simulated user isn't a metronome.
    var shape: (opening: Double, middle: Double, close: Double)
    /// Multiplies real time. 1 = real time; the taste race runs compressed.
    var timeScale: Double = 1

    private var rng: Rng
    private var noise: Double = 0
    private var running = false

    init(
        paceSecPerKm: Double,
        shape: (opening: Double, middle: Double, close: Double) = (1.01, 1.0, 0.97),
        seed: UInt64 = 0x5241_4345_4D45
    ) {
        self.targetPaceSecPerKm = paceSecPerKm
        self.shape = shape
        self.rng = Rng(seed: seed)
    }

    func start() { running = true }
    func stop() { running = false; speed = 0 }

    func tick(dt: Double, raceProgress: Double) {
        guard running else { return }
        let scaled = dt * timeScale

        let shapeMultiplier: Double = raceProgress < 0.33
            ? lerp(shape.opening, shape.middle, raceProgress / 0.33)
            : raceProgress < 0.72
                ? shape.middle
                : lerp(shape.middle, shape.close, (raceProgress - 0.72) / 0.28)

        // Same correlated-noise model as the ghosts. A simulated user that moves
        // at a constant speed makes every gap on screen look scripted.
        noise += (-noise / 8.0) * scaled + 0.014 * sqrt(scaled) * rng.gaussian()
        noise = min(max(noise, -0.045), 0.045)

        let base = 1000 / targetPaceSecPerKm
        speed = max(0.5, base * (1 / shapeMultiplier + noise))
        distance += speed * scaled
    }

    func reset() { distance = 0; speed = 0; noise = 0 }
}

// MARK: - Real GPS

/// CoreLocation-backed. Filters aggressively, because a jittering GPS fix turns
/// the gap readout into a slot machine and destroys trust in the whole screen.
final class GPSMovementSource: NSObject, MovementSource, CLLocationManagerDelegate {
    private(set) var distance: Double = 0
    private(set) var speed: Double = 0
    private(set) var isReliable: Bool = false
    private(set) var fault: MovementFault?

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    /// Smoothed speed. GPS speed is noisy at running pace; raw values make the
    /// pace readout unusable.
    private var speedFilter: Double = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            fault = .noPermission
            return
        default: break
        }
        distance = 0
        lastLocation = nil
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    func tick(dt: Double, raceProgress: Double) {
        // GPS pushes; nothing to integrate. Speed decays if fixes stop arriving
        // so a stalled signal doesn't leave the user's dot gliding forever.
        if let last = lastLocation, Date().timeIntervalSince(last.timestamp) > 4 {
            isReliable = false
            fault = .weakSignal
            speed *= pow(0.5, dt)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy > 0, location.horizontalAccuracy < 35 else { continue }
            guard abs(location.timestamp.timeIntervalSinceNow) < 3 else { continue }

            if let last = lastLocation {
                let delta = location.distance(from: last)
                // Reject teleports — a 20m jump between 1Hz fixes is a fix error,
                // not a human.
                if delta < 20 { distance += delta }
            }
            let raw = max(0, location.speed)
            speedFilter += (raw - speedFilter) * 0.35
            speed = speedFilter
            lastLocation = location
            isReliable = true
            fault = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isReliable = false
        fault = .weakSignal
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted: fault = .noPermission
        case .authorizedAlways, .authorizedWhenInUse:
            fault = nil
            manager.startUpdatingLocation()
        default: break
        }
    }
}
