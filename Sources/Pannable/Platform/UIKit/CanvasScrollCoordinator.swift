#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

/// What the scroll coordinator needs from the canvas it drives.
///
/// A plain Swift protocol, so the generic view controller can adopt it in an extension —
/// which `UIScrollViewDelegate` itself cannot be, since Swift forbids a generic class
/// from conforming to an `@objc` protocol outside its main declaration. Routing through
/// this protocol also keeps the delegate object non-generic, so there is one of it
/// rather than one per specialization.
@MainActor
protocol CanvasScrollHandling: AnyObject {

    /// The view that carries the canvas coordinate space, and the view zooming applies to.
    var canvasContentView: UIView { get }

    /// Whether there is anywhere to pan.
    var canvasHasScrollableContent: Bool { get }

    /// The offset changed: recompute what is visible.
    func canvasDidScroll()

    /// The canvas started or stopped moving; `isAtRest` means deferred work can resume.
    func canvasMotionChanged(isAtRest: Bool)

    /// A pointer drag moved the canvas by this much.
    func canvasPan(by translation: CGPoint)
}

/// The `UIScrollView` and gesture delegate for a canvas.
///
/// Two responsibilities live here, and both are deliberately thin. Scroll callbacks
/// drive virtualization — every offset change asks which items are now visible — so
/// they do no measurement, no allocation, and no re-layout; those are deferred to the
/// moments the canvas is at rest. The gesture side adds pointer drag-to-pan, which a
/// scroll view does not do on its own: a mouse drag or a trackpad click-drag moves
/// nothing, which on iPad and in Mac Catalyst leaves a canvas feeling inert to exactly
/// the input people reach for first.
final class CanvasScrollCoordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    weak var handler: (any CanvasScrollHandling)?

    private weak var scrollView: UIScrollView?
    private var pointerPanRecognizer: UIPanGestureRecognizer?

    /// Attaches to a scroll view as its delegate and installs pointer panning.
    func attach(to scrollView: UIScrollView) {
        self.scrollView = scrollView
        scrollView.delegate = self

        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePointerPan))
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        recognizer.delegate = self
        scrollView.addGestureRecognizer(recognizer)
        pointerPanRecognizer = recognizer
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        handler?.canvasDidScroll()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        handler?.canvasMotionChanged(isAtRest: false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // With no coast to follow, the canvas is already at rest.
        handler?.canvasMotionChanged(isAtRest: !decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        handler?.canvasMotionChanged(isAtRest: true)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        handler?.canvasMotionChanged(isAtRest: true)
    }

    // MARK: - Zoom

    // Zoom is not enabled yet — the scale range stays pinned at 1 — but these hooks
    // belong with the rest of the scroll delegate, and handing back the content view
    // here is what a future `canvasZoom(_:)` needs already in place.

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        handler?.canvasContentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        handler?.canvasDidScroll()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        handler?.canvasMotionChanged(isAtRest: true)
    }

    // MARK: - Pointer panning

    @objc
    private func handlePointerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let scrollView else { return }

        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.translation(in: scrollView)
            // Consume the translation each pass so offsets accumulate, rather than
            // re-applying the whole drag on every event.
            recognizer.setTranslation(.zero, in: scrollView)
            handler?.canvasPan(by: translation)
        case .ended, .cancelled:
            handler?.canvasMotionChanged(isAtRest: true)
        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pointerPanRecognizer else { return true }
        guard let scrollView, let handler else { return false }
        return scrollView.isScrollEnabled && handler.canvasHasScrollableContent
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Running alongside the scroll view's own pan keeps two-finger trackpad
        // scrolling working while a pointer drag is also possible.
        gestureRecognizer === pointerPanRecognizer || other === pointerPanRecognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === pointerPanRecognizer else { return true }
        // A drag that starts on a control belongs to that control, not to the canvas.
        return !(touch.view.map(isInteractive) ?? false)
    }

    private func isInteractive(_ view: UIView) -> Bool {
        var candidate: UIView? = view
        while let current = candidate, current !== scrollView {
            if current is UIControl { return true }
            candidate = current.superview
        }
        return false
    }
}

#endif
