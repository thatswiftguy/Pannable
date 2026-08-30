import CoreGraphics

/// A snapshot of what a canvas is currently showing.
///
/// Observe it with ``View/canvasViewport(_:)`` or ``View/onCanvasViewportChange(_:)``
/// to drive chrome that tracks the pan — a minimap, a coordinate readout, or a
/// fetch that pages in items as they come into range.
public struct CanvasViewport: Equatable, Sendable {

    /// The visible region, in canvas coordinates.
    public var visibleRect: CGRect

    /// The size of the full scrollable canvas.
    public var contentSize: CGSize

    /// Whether the user's finger, mouse, or crown is currently moving the canvas.
    public var isDragging: Bool

    /// Whether the canvas is coasting after a fling.
    public var isDecelerating: Bool

    public init(
        visibleRect: CGRect = .zero,
        contentSize: CGSize = .zero,
        isDragging: Bool = false,
        isDecelerating: Bool = false
    ) {
        self.visibleRect = visibleRect
        self.contentSize = contentSize
        self.isDragging = isDragging
        self.isDecelerating = isDecelerating
    }

    /// Whether the canvas is moving for any reason.
    public var isMoving: Bool { isDragging || isDecelerating }
}
