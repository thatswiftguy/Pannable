#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

/// The UIKit canvas: a scroll view whose content view is the canvas coordinate space,
/// populated with only the items the viewport can currently see.
@MainActor
final class CanvasViewController<Content: View>: UIViewController, CanvasHostControlling {

    let scrollView = CanvasScrollView()
    let contentView = UIView()

    private let engine: CanvasEngine<Content>
    private let scrollCoordinator = CanvasScrollCoordinator()
    private lazy var measurer = ItemMeasurer<Content>(parent: self)
    private lazy var recycler = HostRecycler<Content>(parent: self, container: contentView)

    /// Set by the representable on every update pass.
    var viewportDidChange: (CanvasViewport) -> Void = { _ in }

    /// The reader this canvas reports to, if it is inside one.
    ///
    /// Claimed on appearance rather than on construction: SwiftUI can build more than
    /// one host for a given canvas, and only the one actually on screen has a viewport
    /// worth reporting.
    weak var connection: CanvasConnection? {
        didSet { if isOnScreen { connection?.host = self } }
    }

    private var isOnScreen = false

    private var viewportPublisher = ViewportPublisher()
    private var hasAppliedInitialAnchor = false
    private var isMeasurementScheduled = false
    private var lastLaidOutBounds: CGRect = .zero

    // MARK: - Life cycle

    init(source: CanvasItemSource<Content>, configuration: CanvasConfiguration) {
        self.engine = CanvasEngine(source: source, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollCoordinator.handler = self
        scrollCoordinator.attach(to: scrollView)

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.backgroundColor = .clear
        // The canvas positions everything itself; letting UIKit adjust the offset for
        // safe areas would shift the coordinate space out from under it.
        scrollView.contentInsetAdjustmentBehavior = .never
        // Without this a two-finger trackpad swipe on iPad moves the pointer instead of
        // panning the canvas.
        scrollView.panGestureRecognizer.allowedScrollTypesMask = .all

        scrollView.addSubview(contentView)
        view.addSubview(scrollView)

        applyBehavior()
        resolveAndApplyLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        connection?.host = self
        publishViewport()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isOnScreen = false
        // Only surrender the connection if this host still holds it; a newly appeared
        // host may already have taken over.
        if connection?.host === self { connection?.host = nil }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard scrollView.bounds.size != lastLaidOutBounds.size else {
            updateVisibleItems()
            return
        }
        lastLaidOutBounds = scrollView.bounds

        // The starting position can only be computed once the viewport has a size.
        if !hasAppliedInitialAnchor, scrollView.bounds.width > 0, scrollView.bounds.height > 0 {
            applyInitialAnchor()
            hasAppliedInitialAnchor = true
        }
        updateVisibleItems()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)

        // Text scales with Dynamic Type, so every measurement taken at the old size is
        // now wrong.
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            engine.invalidateMeasurements()
            resolveAndApplyLayout()
        }

        // The backdrop is a rendered bitmap, so an appearance change has to redraw it;
        // a dynamic colour cannot adapt on its own once it is baked into a pattern.
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle
            || previous?.displayScale != traitCollection.displayScale {
            applyBackground()
        }
    }

    // MARK: - Updating from SwiftUI

    func update(source: CanvasItemSource<Content>, configuration: CanvasConfiguration) {
        let outcome = engine.update(source: source, configuration: configuration)

        if outcome.needsBehaviorUpdate {
            applyBehavior()
        }

        if outcome.needsLayout {
            recycler.recycleAll()
            resolveAndApplyLayout()
        } else {
            // Identities held but the views behind them may not have.
            recycler.refreshContent(engine.content(at:))
        }
    }

    // MARK: - Layout

    private func resolveAndApplyLayout() {
        engine.resolve()

        let contentSize = engine.contentSize
        contentView.frame = CGRect(origin: .zero, size: contentSize)
        scrollView.contentSize = contentSize

        updateVisibleItems()
        scheduleMeasurementIfNeeded()
    }

    /// Brings the items intersecting the viewport on screen and recycles the rest.
    ///
    /// This runs on every scroll event, so it does no measurement and no allocation
    /// beyond the index query — that is what keeps a fling smooth.
    func updateVisibleItems() {
        let visibleRect = canvasVisibleRect.insetBy(
            dx: -engine.configuration.overscan,
            dy: -engine.configuration.overscan
        )
        recycler.setVisible(
            engine.visibleIndices(in: visibleRect),
            content: engine.content(at:),
            frame: engine.frame(at:)
        )
        publishViewport()
    }

    private func applyBehavior() {
        let configuration = engine.configuration

        switch configuration.scrollIndicators {
        case .automatic, .visible:
            scrollView.showsHorizontalScrollIndicator = true
            scrollView.showsVerticalScrollIndicator = true
        case .hidden:
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
        }

        switch configuration.bounce {
        case .automatic:
            scrollView.bounces = true
            scrollView.alwaysBounceHorizontal = false
            scrollView.alwaysBounceVertical = false
        case .always:
            scrollView.bounces = true
            scrollView.alwaysBounceHorizontal = true
            scrollView.alwaysBounceVertical = true
        case .never:
            scrollView.bounces = false
            scrollView.alwaysBounceHorizontal = false
            scrollView.alwaysBounceVertical = false
        }

        scrollView.isScrollEnabled = !configuration.isScrollDisabled
        scrollView.decelerationRate = configuration.deceleration == .fast ? .fast : .normal

        applyBackground()
    }

    private func applyBackground() {
        contentView.backgroundColor = engine.configuration.background.patternColor(for: traitCollection)
    }

    private func applyInitialAnchor() {
        let anchor = engine.configuration.initialAnchor
        let travel = maximumContentOffset
        setContentOffset(
            CGPoint(x: travel.x * anchor.x, y: travel.y * anchor.y),
            animated: false
        )
    }

    // MARK: - Measurement

    /// Measures outstanding items across run-loop turns rather than in one blocking
    /// pass, so a canvas over thousands of items still shows something on the first
    /// frame. Estimated sizes stand in until the real ones land.
    private func scheduleMeasurementIfNeeded() {
        guard engine.hasPendingMeasurement, !isMeasurementScheduled else { return }
        isMeasurementScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMeasurementScheduled = false

            // Measuring mid-gesture would compete with the very frames the user is
            // watching; it resumes when the canvas comes to rest.
            guard !self.scrollView.isDragging, !self.scrollView.isDecelerating else {
                self.scheduleMeasurementIfNeeded()
                return
            }

            let finished = self.engine.measureNextChunk { position, proposedWidth in
                self.measurer.measure(self.engine.content(at: position), proposedWidth: proposedWidth)
            }

            if finished {
                // One settle at the end rather than a reflow per chunk, so the content
                // doesn't shuffle repeatedly while it loads.
                self.resolveAndApplyLayout()
            } else {
                self.scheduleMeasurementIfNeeded()
            }
        }
    }

    /// Resumes measurement that was deferred while the canvas was moving.
    func resumeDeferredWork() {
        scheduleMeasurementIfNeeded()
    }

    // MARK: - Offsets

    private var maximumContentOffset: CGPoint {
        let insets = scrollView.adjustedContentInset
        return CGPoint(
            x: max(0, scrollView.contentSize.width - scrollView.bounds.width + insets.left + insets.right),
            y: max(0, scrollView.contentSize.height - scrollView.bounds.height + insets.top + insets.bottom)
        )
    }

    func setContentOffset(_ offset: CGPoint, animated: Bool) {
        let insets = scrollView.adjustedContentInset
        let travel = maximumContentOffset
        let clamped = CGPoint(
            x: min(max(offset.x, -insets.left), travel.x - insets.left),
            y: min(max(offset.y, -insets.top), travel.y - insets.top)
        )
        scrollView.setContentOffset(clamped, animated: animated)
    }

    /// Whether there is anywhere to pan to.
    var hasScrollableContent: Bool {
        scrollView.contentSize.width > scrollView.bounds.width
            || scrollView.contentSize.height > scrollView.bounds.height
    }

    /// Moves the viewport by a delta, clamped to the canvas.
    func panBy(dx: CGFloat, dy: CGFloat) {
        setContentOffset(
            CGPoint(x: scrollView.contentOffset.x + dx, y: scrollView.contentOffset.y + dy),
            animated: false
        )
    }

    /// Reports the viewport, but only when it actually changed.
    ///
    /// See ``ViewportPublisher`` for why the change check matters.
    func publishViewport() {
        let viewport = currentViewport
        guard viewportPublisher.shouldPublish(viewport) else { return }
        viewportDidChange(viewport)
        connection?.viewport = viewport
    }

    // MARK: - CanvasHostControlling

    /// The visible region in canvas coordinates.
    ///
    /// Converting through the content view rather than reading `scrollView.bounds`
    /// keeps this correct under a zoom transform.
    var canvasVisibleRect: CGRect {
        scrollView.convert(scrollView.bounds, to: contentView)
    }

    var currentViewport: CanvasViewport {
        CanvasViewport(
            visibleRect: canvasVisibleRect,
            contentSize: scrollView.contentSize,
            isDragging: scrollView.isDragging,
            isDecelerating: scrollView.isDecelerating
        )
    }

    func frame(forItemWith id: AnyHashable) -> CGRect? {
        engine.frame(forItemWith: id)
    }

    func scrollTo(rect: CGRect, anchor: UnitPoint, animated: Bool) {
        let viewport = scrollView.bounds.size
        // Line up the anchor point of the target rect with the same anchor point of the
        // viewport, so `.center` centers and `.topLeading` tucks it into the corner.
        setContentOffset(
            CGPoint(
                x: rect.minX + rect.width * anchor.x - viewport.width * anchor.x,
                y: rect.minY + rect.height * anchor.y - viewport.height * anchor.y
            ),
            animated: animated
        )
    }
}

// MARK: - CanvasScrollHandling

extension CanvasViewController: CanvasScrollHandling {

    var canvasContentView: UIView { contentView }

    var canvasHasScrollableContent: Bool { hasScrollableContent }

    func canvasDidScroll() {
        updateVisibleItems()
    }

    func canvasMotionChanged(isAtRest: Bool) {
        publishViewport()
        if isAtRest { resumeDeferredWork() }
    }

    func canvasPan(by translation: CGPoint) {
        panBy(dx: -translation.x, dy: -translation.y)
    }
}

#endif
