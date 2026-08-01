import QuartzCore
import UIKit

/// A `CADisplayLink` that actually asks for 120Hz.
///
/// SwiftUI's own animation clock is fine for transitions, but the lane is
/// integrated physics — it needs a real per-frame `dt`, and it needs the system
/// to know we want every frame ProMotion can give us. Without the explicit
/// `CAFrameRateRange` (and `CADisableMinimumFrameDurationOnPhone` in Info.plist)
/// iOS quietly caps this at 60.
@MainActor
final class DisplayLink {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private let onFrame: (Double) -> Void

    /// Ceiling on a single step. If the app is backgrounded or the main thread
    /// stalls, we must not integrate a two-second `dt` and teleport every racer
    /// down the track.
    private let maxStep: Double = 1.0 / 20.0

    init(onFrame: @escaping (Double) -> Void) {
        self.onFrame = onFrame
    }

    func start(preferredFPS: Float = 120) {
        guard link == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 80, maximum: preferredFPS, preferred: preferredFPS
        )
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
    }

    fileprivate func frame(_ link: CADisplayLink) {
        guard lastTimestamp != 0 else {
            lastTimestamp = link.timestamp
            return
        }
        let dt = min(link.timestamp - lastTimestamp, maxStep)
        lastTimestamp = link.timestamp
        onFrame(dt)
    }

    deinit {
        // `link` retains its target, so the proxy — not self — owns the cycle break.
        link?.invalidate()
    }
}

/// CADisplayLink retains its target. The proxy keeps that retain off the owner
/// so a race screen that goes away actually deallocates.
private final class DisplayLinkProxy {
    weak var owner: DisplayLink?
    init(_ owner: DisplayLink) { self.owner = owner }

    @MainActor @objc func step(_ link: CADisplayLink) {
        owner?.frame(link)
    }
}
