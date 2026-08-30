import CoreGraphics
import SwiftUI

/// The state machine every platform host drives.
///
/// It owns the data, the measurements, the resolved frames, and the visibility index —
/// everything except the views themselves. `UIScrollView`, `NSScrollView`, and the
/// watchOS SwiftUI host all differ underneath, but they ask this the same questions in
/// the same order, which is what keeps their behavior from drifting apart.
@MainActor
final class CanvasEngine<Content: View> {

    /// How many items are measured per pass. Sized so a pass stays well inside a frame
    /// even for expensive item views.
    private static var measurementChunkSize: Int { 200 }

    /// Ceiling on a measured dimension. A view with no intrinsic size — a bare `Color`,
    /// say — reports whatever it was proposed, and an unclamped value would poison the
    /// layout with a near-infinite frame.
    private static var maximumMeasuredExtent: CGFloat { 10_000 }

    private(set) var source: CanvasItemSource<Content>
    private(set) var configuration: CanvasConfiguration
    private(set) var resolution: CanvasResolution = .empty

    private var index: SpatialIndex = .empty
    private var sizeCache = SizeCache()

    /// Positions still awaiting measurement, highest first so removal is cheap.
    private var pendingMeasurement: [Int] = []

    init(source: CanvasItemSource<Content>, configuration: CanvasConfiguration) {
        self.source = source
        self.configuration = configuration
    }

    // MARK: - Reading the resolved layout

    var contentSize: CGSize { resolution.contentSize }

    var contentBounds: CGRect { resolution.contentBounds }

    /// Whether measurements are still outstanding.
    var hasPendingMeasurement: Bool { !pendingMeasurement.isEmpty }

    func frame(at position: Int) -> CGRect? {
        resolution.frames.indices.contains(position) ? resolution.frames[position] : nil
    }

    func frame(forItemWith id: AnyHashable) -> CGRect? {
        source.position(of: id).flatMap(frame(at:))
    }

    func content(at position: Int) -> Content {
        source.content(position)
    }

    /// The items intersecting `rect`, in data order.
    func visibleIndices(in rect: CGRect) -> [Int] {
        index.indices(intersecting: rect)
    }

    // MARK: - Updating

    /// Result of folding new inputs in, telling the host what work it now owes.
    struct UpdateOutcome {
        /// The frames must be recomputed.
        var needsLayout: Bool
        /// Scroll view properties changed but the frames did not.
        var needsBehaviorUpdate: Bool
    }

    func update(source newSource: CanvasItemSource<Content>, configuration newConfiguration: CanvasConfiguration) -> UpdateOutcome {
        let identityChanged = newSource.ids != source.ids
        let layoutInvalidated = newConfiguration.invalidatesLayout(comparedTo: configuration)
        let behaviorChanged = newConfiguration != configuration

        // The content closure captures the caller's data, so it must be replaced on
        // every pass even when nothing about identity changed — otherwise items would
        // render from a stale snapshot.
        source = newSource
        configuration = newConfiguration

        if identityChanged {
            // Measurements are keyed by identity, so surviving items keep theirs.
            sizeCache.retain(Set(newSource.ids))
        }

        return UpdateOutcome(
            needsLayout: identityChanged || layoutInvalidated,
            needsBehaviorUpdate: behaviorChanged
        )
    }

    /// Throws away every measurement, for changes that alter how all items size
    /// themselves at once — a Dynamic Type change being the usual cause.
    func invalidateMeasurements() {
        sizeCache.removeAll()
    }

    // MARK: - Resolving

    /// Recomputes every frame from the current sizes.
    ///
    /// Items that have not been measured yet contribute their estimated size, so this
    /// always produces a complete layout — the canvas shows something immediately and
    /// settles as real measurements arrive.
    func resolve() {
        let sizes: [CGSize]

        if let uniform = configuration.itemSize {
            // The fast path: nothing to measure, ever.
            sizes = Array(repeating: uniform, count: source.count)
            pendingMeasurement = []
        } else {
            var outstanding: [Int] = []
            sizes = source.ids.enumerated().map { position, id in
                if let measured = sizeCache[id] { return measured }
                outstanding.append(position)
                return configuration.estimatedItemSize
            }
            pendingMeasurement = outstanding.reversed()
        }

        resolution = LayoutEngine.resolve(
            sizes: sizes,
            layout: configuration.layout,
            contentSize: configuration.contentSize,
            margins: configuration.margins,
            contentAnchor: configuration.contentAnchor,
            layoutDirection: configuration.layoutDirection
        )
        index = SpatialIndex(frames: resolution.frames)
    }

    /// Measures the next batch of unmeasured items.
    ///
    /// - Parameter measure: Produces a size for the item at a position, given the width
    ///   the canvas can offer it.
    /// - Returns: `true` when every item has now been measured, meaning the caller
    ///   should ``resolve()`` to settle the layout.
    func measureNextChunk(_ measure: (Int, CGFloat?) -> CGSize) -> Bool {
        guard !pendingMeasurement.isEmpty else { return false }

        let proposedWidth = proposedItemWidth
        let batch = min(Self.measurementChunkSize, pendingMeasurement.count)

        for _ in 0..<batch {
            let position = pendingMeasurement.removeLast()
            guard let id = source.id(at: position) else { continue }
            sizeCache[id] = measure(position, proposedWidth).clamped(to: Self.maximumMeasuredExtent)
        }

        return pendingMeasurement.isEmpty
    }

    /// The width offered to an item being measured.
    ///
    /// Handing items the canvas's usable width means text wraps and greedy views size
    /// sensibly, rather than every item reporting one enormous line.
    private var proposedItemWidth: CGFloat? {
        LayoutEngine.proposal(
            for: configuration.contentSize,
            horizontalInsets: configuration.margins.leading + configuration.margins.trailing,
            verticalInsets: configuration.margins.top + configuration.margins.bottom
        ).width
    }
}

private extension CGSize {
    func clamped(to maximum: CGFloat) -> CGSize {
        CGSize(
            width: width.isFinite ? min(max(0, width), maximum) : 0,
            height: height.isFinite ? min(max(0, height), maximum) : 0
        )
    }
}
