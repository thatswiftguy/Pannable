import CoreGraphics
import SwiftUI

/// The outcome of resolving a layout against a canvas.
struct CanvasResolution: Equatable, Sendable {

    /// One frame per item, in canvas coordinates.
    var frames: [CGRect]

    /// The size of the scrollable canvas.
    var contentSize: CGSize

    /// Where the item cluster ended up within the canvas.
    var contentBounds: CGRect

    static let empty = CanvasResolution(frames: [], contentSize: .zero, contentBounds: .zero)
}

/// Turns measured item sizes into canvas-space frames.
///
/// This is the whole brain of the component and it is deliberately free of UIKit,
/// AppKit, and SwiftUI view machinery — it takes sizes in and hands frames back. All
/// three platform hosts share it, which is what keeps their behavior identical and
/// makes the hard parts testable without a simulator.
enum LayoutEngine {

    static func resolve<L: CanvasLayout>(
        sizes: [CGSize],
        layout: L,
        contentSize: CanvasContentSize,
        margins: EdgeInsets,
        contentAnchor: UnitPoint,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> CanvasResolution {

        // Measurement can hand back NaN or infinity for a view that hasn't settled.
        // Letting that reach CGRect math would poison every downstream frame.
        let sizes = sizes.map(\.canvasSanitized)

        let isRightToLeft = layoutDirection == .rightToLeft

        // Leading and trailing are sides, not edges, so they swap under RTL.
        let leftInset = isRightToLeft ? margins.trailing : margins.leading
        let rightInset = isRightToLeft ? margins.leading : margins.trailing
        let horizontalInsets = leftInset + rightInset
        let verticalInsets = margins.top + margins.bottom

        let proposal = proposal(for: contentSize, horizontalInsets: horizontalInsets, verticalInsets: verticalInsets)

        var cache = layout.makeCache(itemCount: sizes.count)
        layout.updateCache(&cache, itemCount: sizes.count)
        let placement = layout.place(CanvasLayoutItems(sizes: sizes), in: proposal, cache: &cache)

        // A layout may place items anywhere, negative coordinates included, so shift the
        // cluster to start at the origin before anchoring it.
        let rawBounds = placement.bounds
        let clusterSize = rawBounds.size.canvasSanitized
        var frames = placement.frames.map { frame -> CGRect in
            let normalized = CGRect(
                x: frame.minX - rawBounds.minX,
                y: frame.minY - rawBounds.minY,
                width: frame.width,
                height: frame.height
            )
            guard isRightToLeft else { return normalized }
            // Mirroring the finished cluster gives every layout correct RTL behavior
            // without each one having to reason about it.
            return CGRect(
                x: clusterSize.width - normalized.maxX,
                y: normalized.minY,
                width: normalized.width,
                height: normalized.height
            )
        }

        let resolvedContentSize = resolvedContentSize(
            for: contentSize,
            clusterSize: clusterSize,
            horizontalInsets: horizontalInsets,
            verticalInsets: verticalInsets
        )

        // The box the cluster gets anchored inside.
        let available = CGSize(
            width: resolvedContentSize.width - horizontalInsets,
            height: resolvedContentSize.height - verticalInsets
        )

        let anchorX = isRightToLeft ? 1 - contentAnchor.x : contentAnchor.x
        let anchorY = contentAnchor.y

        // When the cluster overflows a fixed canvas the slack goes negative, which would
        // push content off the leading edge where no amount of panning can reach it.
        // Pinning to the margin keeps the start of the content reachable; the overflow
        // spills off the far edge instead. Use `.atLeast` to grow rather than clip.
        let origin = CGPoint(
            x: leftInset + max(0, available.width - clusterSize.width) * anchorX,
            y: margins.top + max(0, available.height - clusterSize.height) * anchorY
        )

        for index in frames.indices {
            frames[index] = frames[index].offsetBy(dx: origin.x, dy: origin.y)
        }

        return CanvasResolution(
            frames: frames,
            contentSize: resolvedContentSize,
            contentBounds: CGRect(origin: origin, size: clusterSize)
        )
    }

    /// The space offered to the layout: the canvas minus its margins, or unbounded
    /// when the canvas sizes itself to its content.
    static func proposal(
        for contentSize: CanvasContentSize,
        horizontalInsets: CGFloat,
        verticalInsets: CGFloat
    ) -> CanvasProposal {
        switch contentSize.mode {
        case .automatic:
            return .unspecified
        case .fixed(let size), .atLeast(let size):
            return CanvasProposal(
                width: max(0, size.width - horizontalInsets),
                height: max(0, size.height - verticalInsets)
            )
        }
    }

    private static func resolvedContentSize(
        for contentSize: CanvasContentSize,
        clusterSize: CGSize,
        horizontalInsets: CGFloat,
        verticalInsets: CGFloat
    ) -> CGSize {
        let hugging = CGSize(
            width: clusterSize.width + horizontalInsets,
            height: clusterSize.height + verticalInsets
        )
        switch contentSize.mode {
        case .automatic:
            return hugging
        case .fixed(let size):
            return size.canvasSanitized
        case .atLeast(let size):
            let floor = size.canvasSanitized
            return CGSize(
                width: max(floor.width, hugging.width),
                height: max(floor.height, hugging.height)
            )
        }
    }
}

extension CGSize {
    /// This size with non-finite or negative dimensions replaced by zero.
    var canvasSanitized: CGSize {
        CGSize(
            width: width.isFinite ? max(0, width) : 0,
            height: height.isFinite ? max(0, height) : 0
        )
    }
}
