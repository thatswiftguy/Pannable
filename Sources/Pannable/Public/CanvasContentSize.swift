import CoreGraphics

/// The size of a canvas's scrollable coordinate space.
///
/// A canvas lays its items out into a rectangle of this size. Panning moves the
/// viewport around inside that rectangle, so the content size is what determines
/// how far the canvas can travel in each direction.
///
/// ```swift
/// PannableCanvas(stickers, contentSize: .fixed(width: 4000, height: 3000)) { ... }
/// ```
public struct CanvasContentSize: Equatable, Sendable {

    @usableFromInline
    enum Mode: Equatable, Sendable {
        case automatic
        case fixed(CGSize)
        case atLeast(CGSize)
    }

    @usableFromInline
    var mode: Mode

    @usableFromInline
    init(mode: Mode) {
        self.mode = mode
    }

    /// A canvas that hugs its laid-out content, plus the content margins.
    ///
    /// Use this when the canvas should be exactly as large as the items need and
    /// no larger. Layouts that need a wrapping width — ``FlowCanvasLayout``, for
    /// one — fall back to their own heuristics, since an automatic canvas
    /// proposes no width.
    public static var automatic: CanvasContentSize {
        CanvasContentSize(mode: .automatic)
    }

    /// A canvas of exactly this size, regardless of how much room the items need.
    public static func fixed(_ size: CGSize) -> CanvasContentSize {
        CanvasContentSize(mode: .fixed(size))
    }

    /// A canvas of exactly this width and height.
    public static func fixed(width: CGFloat, height: CGFloat) -> CanvasContentSize {
        .fixed(CGSize(width: width, height: height))
    }

    /// A canvas at least this large, growing if the content needs more room.
    public static func atLeast(_ size: CGSize) -> CanvasContentSize {
        CanvasContentSize(mode: .atLeast(size))
    }

    /// A canvas at least this wide and tall, growing if the content needs more room.
    public static func atLeast(width: CGFloat, height: CGFloat) -> CanvasContentSize {
        .atLeast(CGSize(width: width, height: height))
    }
}
