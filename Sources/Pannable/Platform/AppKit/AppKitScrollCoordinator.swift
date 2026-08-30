#if os(macOS)

import AppKit
import SwiftUI

/// What the AppKit scroll coordinator needs from the canvas it drives.
@MainActor
protocol AppKitCanvasScrollHandling: AnyObject {
    var canvasHasScrollableContent: Bool { get }
    func canvasDidScroll()
    func canvasMotionChanged(isAtRest: Bool)
    func canvasPan(by translation: CGPoint)
    func canvasIsInteractiveTarget(_ view: NSView?) -> Bool
}

/// The scrolling and gesture delegate for the AppKit canvas.
///
/// AppKit has no `UIScrollViewDelegate`; the equivalents are notifications, so this
/// class subscribes to them. Clip-view bounds changes stand in for
/// `scrollViewDidScroll`, and the live-scroll notifications give the same
/// began/ended signal that `willBeginDragging` and `didEndDecelerating` do — which is
/// what lets measurement be deferred until the canvas is at rest, exactly as on iOS.
///
/// It also adds primary-button drag-to-pan. A scroll view already handles the wheel and
/// two-finger trackpad scrolling, but not dragging the canvas itself, which is the
/// gesture people reach for on a canvas.
@MainActor
final class AppKitScrollCoordinator: NSObject, NSGestureRecognizerDelegate {

    weak var handler: (any AppKitCanvasScrollHandling)?

    private weak var scrollView: NSScrollView?
    private var panRecognizer: NSPanGestureRecognizer?

    func attach(to scrollView: NSScrollView) {
        self.scrollView = scrollView

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true

        // Selector-based observation rather than the block API: the block form demands a
        // `@Sendable` closure, and this coordinator is main-actor state by nature.
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        center.addObserver(
            self,
            selector: #selector(liveScrollWillStart),
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        center.addObserver(
            self,
            selector: #selector(liveScrollDidEnd),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )

        let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePan))
        recognizer.buttonMask = 0x1
        recognizer.delegate = self
        scrollView.addGestureRecognizer(recognizer)
        panRecognizer = recognizer
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Scroll notifications

    // AppKit's stand-ins for `scrollViewDidScroll`, `willBeginDragging`, and
    // `didEndDecelerating`. Notifications always arrive on the main thread, but the
    // selector-based entry points carry no isolation of their own.

    @objc
    private func clipViewBoundsDidChange() {
        handler?.canvasDidScroll()
    }

    @objc
    private func liveScrollWillStart() {
        handler?.canvasMotionChanged(isAtRest: false)
    }

    @objc
    private func liveScrollDidEnd() {
        handler?.canvasMotionChanged(isAtRest: true)
    }

    // MARK: - Drag to pan

    // Gesture actions always arrive on the main thread, but the selector-based entry
    // point carries no isolation of its own.
    @objc
    private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard let scrollView else { return }

        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.translation(in: scrollView)
            // Consume the translation each pass so offsets accumulate rather than
            // re-applying the whole drag on every event.
            recognizer.setTranslation(.zero, in: scrollView)
            handler?.canvasPan(by: translation)
        case .ended, .cancelled:
            handler?.canvasMotionChanged(isAtRest: true)
        default:
            break
        }
    }

    // MARK: - NSGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard gestureRecognizer === panRecognizer else { return true }
        guard let handler else { return false }
        return handler.canvasHasScrollableContent
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer
    ) -> Bool {
        gestureRecognizer === panRecognizer || other === panRecognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        guard gestureRecognizer === panRecognizer, let scrollView, let handler else { return true }
        // A drag that starts on a control belongs to that control, not to the canvas.
        let location = scrollView.convert(event.locationInWindow, from: nil)
        return !handler.canvasIsInteractiveTarget(scrollView.hitTest(location))
    }
}

#endif
