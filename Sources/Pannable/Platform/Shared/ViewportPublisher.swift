import CoreGraphics

/// Gates viewport reporting so a canvas cannot drive itself in circles.
///
/// This is load-bearing, not an optimization. Reporting a viewport writes SwiftUI
/// state — a binding, or a `CanvasReader`'s observable object — which re-evaluates the
/// body, which calls back into the host's update path, which reports again. Without a
/// change check that round trip never settles: the canvas spins in an unbounded update
/// loop and stops responding to input entirely.
///
/// All three hosts share this rather than each remembering the last value themselves,
/// so the invariant is stated in one place and can be tested without a view hierarchy.
struct ViewportPublisher {

    private var lastPublished: CanvasViewport?

    init() {}

    /// Whether `viewport` is worth reporting, recording it as the latest if so.
    mutating func shouldPublish(_ viewport: CanvasViewport) -> Bool {
        guard viewport != lastPublished else { return false }
        lastPublished = viewport
        return true
    }

    /// Forgets the last reported viewport, so the next one always publishes.
    mutating func reset() {
        lastPublished = nil
    }
}
