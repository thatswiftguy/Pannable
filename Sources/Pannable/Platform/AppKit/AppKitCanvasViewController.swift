#if os(macOS)

import AppKit
import SwiftUI

/// The AppKit canvas: an `NSScrollView` over a flipped document view that holds only
/// the items the viewport can currently see.
@MainActor
final class CanvasViewController<Content: View>: NSViewController, CanvasHostControlling {

    let scrollView = NSScrollView()
    let contentView = FlippedCanvasContentView()

    private let engine: CanvasEngine<Content>
    private let scrollCoordinator = AppKitScrollCoordinator()
    private lazy var measurer = AppKitItemMeasurer<Content>(parent: self)
    private lazy var recycler = AppKitHostRecycler<Content>(parent: self, container: contentView)

    var viewportDidChange: (CanvasViewport) -> Void = { _ in }

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
    private var isMoving = false
    private var lastLaidOutSize: CGSize = .zero

    init(source: CanvasItemSource<Content>, configuration: CanvasConfiguration) {
        self.engine = CanvasEngine(source: source, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.documentView = contentView
        scrollView.allowsMagnification = false

        view.addSubview(scrollView)

        scrollCoordinator.handler = self
        scrollCoordinator.attach(to: scrollView)

        applyBehavior()
        resolveAndApplyLayout()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        isOnScreen = true
        connection?.host = self
        publishViewport()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        isOnScreen = false
        if connection?.host === self { connection?.host = nil }
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        guard scrollView.bounds.size != lastLaidOutSize else {
            updateVisibleItems()
            return
        }
        lastLaidOutSize = scrollView.bounds.size

        if !hasAppliedInitialAnchor, scrollView.bounds.width > 0, scrollView.bounds.height > 0 {
            applyInitialAnchor()
            hasAppliedInitialAnchor = true
        }
        updateVisibleItems()
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
            recycler.refreshContent(engine.content(at:))
        }
    }

    // MARK: - Layout

    private func resolveAndApplyLayout() {
        engine.resolve()

        contentView.frame = CGRect(origin: .zero, size: engine.contentSize)

        updateVisibleItems()
        scheduleMeasurementIfNeeded()
    }

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
        case .automatic:
            scrollView.hasHorizontalScroller = true
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
        case .visible:
            scrollView.hasHorizontalScroller = true
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = false
        case .hidden:
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = false
        }

        // AppKit has no bounce toggle; rubber-banding is a system behavior. The other
        // behaviors map directly.
        scrollView.verticalScrollElasticity = configuration.bounce == .never ? .none : .automatic
        scrollView.horizontalScrollElasticity = configuration.bounce == .never ? .none : .automatic
    }

    private func applyInitialAnchor() {
        let anchor = engine.configuration.initialAnchor
        let travel = maximumOrigin
        setVisibleOrigin(CGPoint(x: travel.x * anchor.x, y: travel.y * anchor.y), animated: false)
    }

    // MARK: - Measurement

    /// Measures outstanding items across run-loop turns rather than in one blocking
    /// pass, so a canvas over thousands of items still shows something immediately.
    private func scheduleMeasurementIfNeeded() {
        guard engine.hasPendingMeasurement, !isMeasurementScheduled else { return }
        isMeasurementScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMeasurementScheduled = false

            guard !self.isMoving else {
                self.scheduleMeasurementIfNeeded()
                return
            }

            let finished = self.engine.measureNextChunk { position, proposedWidth in
                self.measurer.measure(self.engine.content(at: position), proposedWidth: proposedWidth)
            }

            if finished {
                // One settle at the end rather than a reflow per chunk.
                self.resolveAndApplyLayout()
            } else {
                self.scheduleMeasurementIfNeeded()
            }
        }
    }

    func resumeDeferredWork() {
        scheduleMeasurementIfNeeded()
    }

    // MARK: - Offsets

    var canvasVisibleRect: CGRect { scrollView.documentVisibleRect }

    private var maximumOrigin: CGPoint {
        CGPoint(
            x: max(0, engine.contentSize.width - scrollView.contentSize.width),
            y: max(0, engine.contentSize.height - scrollView.contentSize.height)
        )
    }

    func setVisibleOrigin(_ origin: CGPoint, animated: Bool) {
        let travel = maximumOrigin
        let clamped = CGPoint(
            x: min(max(origin.x, 0), travel.x),
            y: min(max(origin.y, 0), travel.y)
        )
        let clipView = scrollView.contentView

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(clamped)
            } completionHandler: { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.publishViewport()
                    self.resumeDeferredWork()
                }
            }
        } else {
            clipView.setBoundsOrigin(clamped)
        }
        scrollView.reflectScrolledClipView(clipView)
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

    var currentViewport: CanvasViewport {
        CanvasViewport(
            visibleRect: canvasVisibleRect,
            contentSize: engine.contentSize,
            isDragging: isMoving,
            isDecelerating: false
        )
    }

    func frame(forItemWith id: AnyHashable) -> CGRect? {
        engine.frame(forItemWith: id)
    }

    func scrollTo(rect: CGRect, anchor: UnitPoint, animated: Bool) {
        let viewport = scrollView.contentSize
        setVisibleOrigin(
            CGPoint(
                x: rect.minX + rect.width * anchor.x - viewport.width * anchor.x,
                y: rect.minY + rect.height * anchor.y - viewport.height * anchor.y
            ),
            animated: animated
        )
    }
}

// MARK: - AppKitCanvasScrollHandling

extension CanvasViewController: AppKitCanvasScrollHandling {

    var canvasHasScrollableContent: Bool {
        engine.contentSize.width > scrollView.contentSize.width
            || engine.contentSize.height > scrollView.contentSize.height
    }

    func canvasDidScroll() {
        updateVisibleItems()
    }

    func canvasMotionChanged(isAtRest: Bool) {
        isMoving = !isAtRest
        publishViewport()
        if isAtRest { resumeDeferredWork() }
    }

    func canvasPan(by translation: CGPoint) {
        let origin = scrollView.contentView.bounds.origin
        // The document view is flipped, so both axes move opposite the drag.
        setVisibleOrigin(
            CGPoint(x: origin.x - translation.x, y: origin.y - translation.y),
            animated: false
        )
    }

    func canvasIsInteractiveTarget(_ view: NSView?) -> Bool {
        var candidate = view
        while let current = candidate, current !== scrollView {
            if current is NSControl { return true }
            candidate = current.superview
        }
        return false
    }
}

#endif
