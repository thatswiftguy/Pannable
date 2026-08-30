import CoreGraphics

/// A type that arranges a canvas's items into a cluster of frames.
///
/// The protocol deliberately mirrors SwiftUI's `Layout`: you build a cache, then
/// place items. The crucial difference is that a canvas layout works on *sizes*
/// rather than on live subviews. That is what lets a canvas position ten thousand
/// items without building ten thousand views — only the ones the viewport can
/// actually see are ever instantiated.
///
/// A layout doesn't know the canvas exists. Place items wherever is natural,
/// including at negative coordinates; the canvas normalizes the resulting cluster
/// and anchors it according to ``View/canvasContentAnchor(_:)``.
///
/// ```swift
/// struct RingCanvasLayout: CanvasLayout {
///     var radius: CGFloat
///
///     func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
///         let step = (2 * .pi) / CGFloat(max(items.count, 1))
///         let frames = items.map { item in
///             let angle = step * CGFloat(item.index)
///             return CGRect(
///                 origin: CGPoint(x: radius * cos(angle) - item.size.width / 2,
///                                 y: radius * sin(angle) - item.size.height / 2),
///                 size: item.size
///             )
///         }
///         return CanvasLayoutResult(frames: frames)
///     }
/// }
/// ```
public protocol CanvasLayout: Sendable {

    /// Storage a layout can carry across placement passes.
    associatedtype Cache = Void

    /// Creates the layout's cache. Defaults to `()` for layouts that need none.
    func makeCache(itemCount: Int) -> Cache

    /// Updates an existing cache for a new item count. Does nothing by default.
    func updateCache(_ cache: inout Cache, itemCount: Int)

    /// Places every item, returning their frames in the layout's own coordinate space.
    ///
    /// - Parameters:
    ///   - items: The items to place, each carrying its index and measured size.
    ///   - proposal: The space available. Either dimension may be `nil`, meaning
    ///     unbounded — which happens when the canvas uses ``CanvasContentSize/automatic``.
    ///   - cache: The layout's cache.
    /// - Returns: A frame per item, in the same order as `items`.
    func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Cache) -> CanvasLayoutResult
}

extension CanvasLayout where Cache == Void {
    public func makeCache(itemCount: Int) -> Void { () }
}

extension CanvasLayout {
    public func updateCache(_ cache: inout Cache, itemCount: Int) {}
}

// MARK: - Placement inputs

/// The space a canvas offers its layout.
///
/// A `nil` dimension means unbounded, exactly as `nil` does in SwiftUI's
/// `ProposedViewSize`.
public struct CanvasProposal: Equatable, Sendable {

    /// The available width, or `nil` if unbounded.
    public var width: CGFloat?

    /// The available height, or `nil` if unbounded.
    public var height: CGFloat?

    public init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    /// A proposal with no constraint in either dimension.
    public static var unspecified: CanvasProposal {
        CanvasProposal(width: nil, height: nil)
    }
}

/// A single item awaiting placement.
public struct CanvasLayoutItem: Equatable, Sendable {

    /// The item's position in the canvas's data, starting at zero.
    public var index: Int

    /// The size the item's view wants to occupy.
    public var size: CGSize

    public init(index: Int, size: CGSize) {
        self.index = index
        self.size = size
    }
}

/// The collection of items handed to a ``CanvasLayout``.
public struct CanvasLayoutItems: RandomAccessCollection, Sendable {

    public typealias Element = CanvasLayoutItem
    public typealias Index = Int

    @usableFromInline
    var storage: [CanvasLayoutItem]

    @usableFromInline
    init(_ storage: [CanvasLayoutItem]) {
        self.storage = storage
    }

    /// Creates items from a list of sizes, indexed in order.
    public init(sizes: [CGSize]) {
        self.storage = sizes.enumerated().map { CanvasLayoutItem(index: $0.offset, size: $0.element) }
    }

    @inlinable public var startIndex: Int { storage.startIndex }
    @inlinable public var endIndex: Int { storage.endIndex }
    @inlinable public subscript(position: Int) -> CanvasLayoutItem { storage[position] }

    /// Every item's size, in order.
    @inlinable public var sizes: [CGSize] { storage.map(\.size) }
}

/// The frames a ``CanvasLayout`` produced.
public struct CanvasLayoutResult: Equatable, Sendable {

    /// One frame per item, in the order the items were given.
    public var frames: [CGRect]

    public init(frames: [CGRect]) {
        self.frames = frames
    }

    /// The union of every frame, or `.zero` when there are no items.
    public var bounds: CGRect {
        guard !frames.isEmpty else { return .zero }
        let union = frames.reduce(CGRect.null) { $0.union($1) }
        return union.isNull ? .zero : union
    }
}
