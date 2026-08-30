import CoreGraphics
import SwiftUI

extension View {

    // MARK: - Placement

    /// Sets how a canvas arranges its items.
    ///
    /// Defaults to ``CanvasLayout/flow``.
    ///
    /// ```swift
    /// .canvasLayout(.grid(columns: 6, horizontalSpacing: 16, verticalSpacing: 16))
    /// ```
    public func canvasLayout(_ layout: some CanvasLayout) -> some View {
        environment(\.canvasLayout, AnyCanvasLayout(layout))
    }

    /// Sets where the item cluster sits within the canvas.
    ///
    /// This is the point items are packed around: `.topLeading` starts them in the
    /// corner, `.center` gathers them in the middle of the canvas. It has no effect
    /// when the content already fills the canvas. Defaults to `.center`.
    public func canvasContentAnchor(_ anchor: UnitPoint) -> some View {
        environment(\.canvasContentAnchor, anchor)
    }

    /// Sets where the viewport is positioned when the canvas first appears.
    ///
    /// Independent of ``canvasContentAnchor(_:)`` — content can be packed in the
    /// corner while the viewport opens on the middle of the canvas. Defaults to `.center`.
    public func canvasInitialAnchor(_ anchor: UnitPoint) -> some View {
        environment(\.canvasInitialAnchor, anchor)
    }

    /// Sets the margins between the canvas edges and its item cluster.
    public func canvasContentMargins(_ insets: EdgeInsets) -> some View {
        environment(\.canvasContentMargins, insets)
    }

    /// Sets a uniform margin on all four canvas edges.
    public func canvasContentMargins(_ length: CGFloat) -> some View {
        environment(
            \.canvasContentMargins,
            EdgeInsets(top: length, leading: length, bottom: length, trailing: length)
        )
    }

    // MARK: - Item sizing

    /// Gives every item the same size, skipping measurement entirely.
    ///
    /// This is the fast path. Without it a canvas measures each item's view to find its
    /// size, which is fine for hundreds of items but real work for thousands. When
    /// every item is the same size — a grid of tiles, say — this avoids it completely.
    public func canvasItemSize(_ size: CGSize) -> some View {
        environment(\.canvasItemSize, size)
    }

    /// Sets the size a canvas assumes for items it has not measured yet.
    ///
    /// Serves the same purpose as `UITableView.estimatedRowHeight`: the canvas can lay
    /// out and show something immediately, then settle once real measurements arrive.
    /// The closer the estimate, the less the content shifts when it does.
    public func canvasEstimatedItemSize(_ size: CGSize) -> some View {
        environment(\.canvasEstimatedItemSize, size)
    }

    // MARK: - Behavior

    /// Sets whether the canvas shows scroll indicators.
    public func canvasScrollIndicators(_ visibility: CanvasScrollIndicatorVisibility) -> some View {
        environment(\.canvasScrollIndicators, visibility)
    }

    /// Sets how the canvas behaves when panned past its edges.
    public func canvasBounce(_ behavior: CanvasBounceBehavior) -> some View {
        environment(\.canvasBounce, behavior)
    }

    /// Disables panning without disabling the items themselves.
    public func canvasScrollDisabled(_ disabled: Bool = true) -> some View {
        environment(\.canvasScrollDisabled, disabled)
    }

    /// Sets how quickly the canvas coasts to a stop after a fling.
    public func canvasDeceleration(_ rate: CanvasDecelerationRate) -> some View {
        environment(\.canvasDeceleration, rate)
    }

    /// Sets how far beyond the visible area the canvas keeps items ready.
    ///
    /// A wider margin means fewer views appearing mid-pan, at the cost of holding more
    /// of them. The default suits most content; reach for this only when profiling says
    /// to. Values below zero are treated as zero.
    public func canvasOverscan(_ margin: CGFloat) -> some View {
        environment(\.canvasOverscan, max(0, margin))
    }
}
