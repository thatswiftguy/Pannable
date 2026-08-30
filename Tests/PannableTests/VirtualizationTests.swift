import CoreGraphics
import SwiftUI
import Testing
@testable import Pannable

/// The promise that makes this component viable at scale: what the canvas builds is
/// proportional to what the viewport can see, not to how much data there is.
@Suite("Virtualization")
struct VirtualizationTests {

    private static let itemCount = 5_000
    private static let tile = CGSize(width: 160, height: 160)
    private static let viewport = CGSize(width: 390, height: 844)

    private func resolveLargeCanvas() -> CanvasResolution {
        LayoutEngine.resolve(
            sizes: Array(repeating: Self.tile, count: Self.itemCount),
            layout: GridCanvasLayout(columns: 71, horizontalSpacing: 8, verticalSpacing: 8),
            contentSize: .automatic,
            margins: EdgeInsets(),
            contentAnchor: .center
        )
    }

    @Test("A viewport panned across thousands of items never sees more than a screenful")
    func visibleCountTracksViewportNotDataSize() {
        let resolution = resolveLargeCanvas()
        let index = SpatialIndex(frames: resolution.frames)

        // A 390x844 viewport over 168pt cells spans at most 4 columns by 7 rows.
        let theoreticalMaximum = 4 * 7
        var observedMaximum = 0

        for step in 0...200 {
            let progress = CGFloat(step) / 200
            let rect = CGRect(
                origin: CGPoint(
                    x: progress * (resolution.contentSize.width - Self.viewport.width),
                    y: progress * (resolution.contentSize.height - Self.viewport.height)
                ),
                size: Self.viewport
            )
            observedMaximum = max(observedMaximum, index.indices(intersecting: rect).count)
        }

        #expect(observedMaximum <= theoreticalMaximum,
                "a single viewport held \(observedMaximum) items, above the \(theoreticalMaximum) it can physically show")
        #expect(observedMaximum * 100 < Self.itemCount,
                "hosting \(observedMaximum) of \(Self.itemCount) items is not virtualization")
    }

    @Test("Every item is reachable by panning; none are stranded off-canvas")
    func fullSweepReachesEveryItem() {
        let resolution = resolveLargeCanvas()
        let index = SpatialIndex(frames: resolution.frames)

        // Sweep the whole canvas in viewport-sized steps with a little overlap, and
        // collect everything seen along the way.
        var seen = Set<Int>()
        let strideX = Self.viewport.width * 0.75
        let strideY = Self.viewport.height * 0.75

        var y: CGFloat = 0
        while y < resolution.contentSize.height {
            var x: CGFloat = 0
            while x < resolution.contentSize.width {
                seen.formUnion(index.indices(intersecting: CGRect(origin: CGPoint(x: x, y: y), size: Self.viewport)))
                x += strideX
            }
            y += strideY
        }

        #expect(seen.count == Self.itemCount,
                "\(Self.itemCount - seen.count) items could never be panned to")
    }

    @Test("Setting a uniform item size skips measurement entirely")
    @MainActor
    func uniformItemSizeNeedsNoMeasurement() {
        let source = CanvasItemSource<EmptyView>(ids: (0..<1_000).map(AnyHashable.init)) { _ in EmptyView() }
        let engine = CanvasEngine(source: source, configuration: .test(itemSize: CGSize(width: 40, height: 40)))

        engine.resolve()

        #expect(!engine.hasPendingMeasurement)
        #expect(engine.frame(at: 0)?.size == CGSize(width: 40, height: 40))
    }

    @Test("Without a uniform size, every item is queued for measurement and estimated meanwhile")
    @MainActor
    func unmeasuredItemsUseTheEstimate() {
        let source = CanvasItemSource<EmptyView>(ids: (0..<10).map(AnyHashable.init)) { _ in EmptyView() }
        let engine = CanvasEngine(source: source, configuration: .test(estimatedItemSize: CGSize(width: 90, height: 70)))

        engine.resolve()

        #expect(engine.hasPendingMeasurement)
        // The layout is complete and usable before anything has actually been measured.
        #expect(engine.frame(at: 0)?.size == CGSize(width: 90, height: 70))
        #expect(engine.frame(at: 9) != nil)

        // Feeding real sizes in and settling replaces the estimates.
        while !engine.measureNextChunk({ _, _ in CGSize(width: 30, height: 20) }) {}
        engine.resolve()

        #expect(!engine.hasPendingMeasurement)
        #expect(engine.frame(at: 0)?.size == CGSize(width: 30, height: 20))
    }

    @Test("Measurements survive a data change that keeps identities")
    @MainActor
    func measurementsAreKeptAcrossReorderingByIdentity() {
        let ids = (0..<5).map(AnyHashable.init)
        let engine = CanvasEngine(
            source: CanvasItemSource<EmptyView>(ids: ids) { _ in EmptyView() },
            configuration: .test()
        )
        engine.resolve()
        while !engine.measureNextChunk({ _, _ in CGSize(width: 50, height: 50) }) {}
        engine.resolve()

        // Same items, reversed order, plus one new one.
        let reordered = Array(ids.reversed()) + [AnyHashable(99)]
        _ = engine.update(
            source: CanvasItemSource<EmptyView>(ids: reordered) { _ in EmptyView() },
            configuration: .test()
        )
        engine.resolve()

        // Only the newcomer needs measuring; the five survivors kept their sizes.
        #expect(engine.hasPendingMeasurement)
        #expect(engine.frame(at: 0)?.size == CGSize(width: 50, height: 50))
        #expect(engine.frame(at: 5)?.size == CanvasConfiguration.test().estimatedItemSize)
    }
}

extension CanvasConfiguration {
    /// A configuration with predictable defaults for tests.
    static func test(
        layout: some CanvasLayout = GridCanvasLayout(columns: 4, horizontalSpacing: 0, verticalSpacing: 0),
        itemSize: CGSize? = nil,
        estimatedItemSize: CGSize = CGSize(width: 120, height: 120)
    ) -> CanvasConfiguration {
        CanvasConfiguration(
            layout: AnyCanvasLayout(layout),
            contentSize: .automatic,
            contentAnchor: .topLeading,
            initialAnchor: .center,
            margins: EdgeInsets(),
            itemSize: itemSize,
            estimatedItemSize: estimatedItemSize,
            scrollIndicators: .automatic,
            bounce: .automatic,
            isScrollDisabled: false,
            deceleration: .normal,
            overscan: 0,
            background: .none,
            layoutDirection: .leftToRight
        )
    }
}

/// The canvas reports its viewport into SwiftUI state, and SwiftUI answers by calling
/// back into the host. These lock in the guard that keeps that round trip from becoming
/// an unbounded update loop.
@Suite("Viewport publishing")
struct ViewportPublisherTests {

    @Test("An unchanged viewport is not republished")
    func repeatedValuesArePublishedOnce() {
        var publisher = ViewportPublisher()
        let viewport = CanvasViewport(
            visibleRect: CGRect(x: 10, y: 20, width: 300, height: 400),
            contentSize: CGSize(width: 1000, height: 1000)
        )

        let first = publisher.shouldPublish(viewport)
        // The re-entrant calls SwiftUI makes right after must not publish again, or the
        // canvas never settles.
        let second = publisher.shouldPublish(viewport)
        let third = publisher.shouldPublish(viewport)

        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test("A genuine change is published")
    func changedValuesArePublished() {
        var publisher = ViewportPublisher()

        let initial = publisher.shouldPublish(CanvasViewport(visibleRect: CGRect(x: 0, y: 0, width: 300, height: 400)))
        let moved = publisher.shouldPublish(CanvasViewport(visibleRect: CGRect(x: 0, y: 40, width: 300, height: 400)))
        let repeated = publisher.shouldPublish(CanvasViewport(visibleRect: CGRect(x: 0, y: 40, width: 300, height: 400)))

        #expect(initial)
        #expect(moved)
        #expect(!repeated)
    }

    @Test("Every field of the viewport counts as a change", arguments: [
        CanvasViewport(visibleRect: CGRect(x: 1, y: 0, width: 300, height: 400)),
        CanvasViewport(visibleRect: CGRect(x: 0, y: 0, width: 300, height: 400), contentSize: CGSize(width: 10, height: 0)),
        CanvasViewport(visibleRect: CGRect(x: 0, y: 0, width: 300, height: 400), isDragging: true),
        CanvasViewport(visibleRect: CGRect(x: 0, y: 0, width: 300, height: 400), isDecelerating: true),
    ])
    func everyFieldParticipates(changed: CanvasViewport) {
        var publisher = ViewportPublisher()

        let baseline = publisher.shouldPublish(CanvasViewport(visibleRect: CGRect(x: 0, y: 0, width: 300, height: 400)))
        let published = publisher.shouldPublish(changed)

        #expect(baseline)
        #expect(published, "a change to this field must reach observers")
    }

    @Test("Resetting forces the next viewport to publish")
    func resetForcesRepublish() {
        var publisher = ViewportPublisher()
        let viewport = CanvasViewport(contentSize: CGSize(width: 500, height: 500))

        let first = publisher.shouldPublish(viewport)
        let suppressed = publisher.shouldPublish(viewport)
        publisher.reset()
        let afterReset = publisher.shouldPublish(viewport)

        #expect(first)
        #expect(!suppressed)
        #expect(afterReset)
    }
}
