import CoreGraphics
import SwiftUI

/// A pannable two-dimensional canvas that lays out a collection of items.
///
/// A canvas has a width and a height, and items are arranged inside it by a
/// ``CanvasLayout`` anchored wherever you choose. The viewport pans around that space;
/// only the items it can actually reach are built, so a canvas over thousands of items
/// costs about what one screenful costs.
///
/// ```swift
/// PannableCanvas(stickers, contentSize: .fixed(width: 4000, height: 3000)) { sticker in
///     StickerCard(sticker: sticker)
/// }
/// .canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
/// .canvasContentAnchor(.center)
/// .canvasInitialAnchor(.center)
/// ```
///
/// Items are identified the same way `ForEach` identifies them — through `Identifiable`,
/// through an `id` key path, or by position for a constant range. Identity is what lets
/// the canvas keep an item's measured size across a data change instead of measuring
/// everything again.
///
/// ## Topics
///
/// ### Arranging items
/// - ``SwiftUI/View/canvasLayout(_:)``
/// - ``SwiftUI/View/canvasContentAnchor(_:)``
/// - ``SwiftUI/View/canvasContentMargins(_:)-1x0lp``
///
/// ### Sizing items
/// - ``SwiftUI/View/canvasItemSize(_:)``
/// - ``SwiftUI/View/canvasEstimatedItemSize(_:)``
///
/// ### Controlling the viewport
/// - ``CanvasReader``
/// - ``CanvasProxy``
/// - ``SwiftUI/View/canvasInitialAnchor(_:)``
@MainActor
public struct PannableCanvas<Data, ID, Content>: View
where Data: RandomAccessCollection, ID: Hashable, Content: View {

    private let source: CanvasItemSource<Content>
    private let contentSize: CanvasContentSize

    @Environment(\.canvasLayout) private var layout
    @Environment(\.canvasContentAnchor) private var contentAnchor
    @Environment(\.canvasInitialAnchor) private var initialAnchor
    @Environment(\.canvasContentMargins) private var margins
    @Environment(\.canvasItemSize) private var itemSize
    @Environment(\.canvasEstimatedItemSize) private var estimatedItemSize
    @Environment(\.canvasScrollIndicators) private var scrollIndicators
    @Environment(\.canvasBounce) private var bounce
    @Environment(\.canvasScrollDisabled) private var isScrollDisabled
    @Environment(\.canvasDeceleration) private var deceleration
    @Environment(\.canvasOverscan) private var overscan
    @Environment(\.canvasBackground) private var background
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.canvasConnection) private var connection
    @Environment(\.canvasViewportAction) private var viewportAction

    // MARK: - Initializers

    /// Creates a canvas over identifiable data.
    ///
    /// - Parameters:
    ///   - data: The items to lay out.
    ///   - contentSize: How large the canvas should be. Defaults to
    ///     ``CanvasContentSize/automatic``, which sizes it to its content.
    ///   - content: Builds the view for an item.
    public init(
        _ data: Data,
        contentSize: CanvasContentSize = .automatic,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) where Data.Element: Identifiable, ID == Data.Element.ID {
        self.source = CanvasItemSource(data: data, id: \.id, content: content)
        self.contentSize = contentSize
    }

    /// Creates a canvas over data identified by a key path.
    ///
    /// - Parameters:
    ///   - data: The items to lay out.
    ///   - id: A key path to the property that identifies an item.
    ///   - contentSize: How large the canvas should be.
    ///   - content: Builds the view for an item.
    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        contentSize: CanvasContentSize = .automatic,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.source = CanvasItemSource(data: data, id: id, content: content)
        self.contentSize = contentSize
    }

    /// Creates a canvas over a constant range, identified by position.
    ///
    /// As with `ForEach`, the range must not change between updates.
    public init(
        _ data: Range<Int>,
        contentSize: CanvasContentSize = .automatic,
        @ViewBuilder content: @escaping (Int) -> Content
    ) where Data == Range<Int>, ID == Int {
        self.source = CanvasItemSource(data: data, id: \.self, content: content)
        self.contentSize = contentSize
    }

    // MARK: - Body

    private var configuration: CanvasConfiguration {
        CanvasConfiguration(
            layout: layout,
            contentSize: contentSize,
            contentAnchor: contentAnchor,
            initialAnchor: initialAnchor,
            margins: margins,
            itemSize: itemSize,
            estimatedItemSize: estimatedItemSize,
            scrollIndicators: scrollIndicators,
            bounce: bounce,
            isScrollDisabled: isScrollDisabled,
            deceleration: deceleration,
            overscan: overscan,
            background: background,
            layoutDirection: layoutDirection
        )
    }

    public var body: some View {
        CanvasHostView(
            source: source,
            configuration: configuration,
            connection: connection,
            viewportDidChange: { viewport in
                viewportAction?.handler(viewport)
            }
        )
    }
}

/// Picks the platform host. Each platform's canvas is a different thing underneath —
/// a `UIScrollView`, an `NSScrollView`, or a SwiftUI offset on watchOS where neither
/// exists — but they all take the same inputs.
private struct CanvasHostView<Content: View>: View {

    var source: CanvasItemSource<Content>
    var configuration: CanvasConfiguration
    var connection: CanvasConnection?
    var viewportDidChange: (CanvasViewport) -> Void

    var body: some View {
        #if canImport(UIKit) && !os(watchOS)
        CanvasRepresentable(
            source: source,
            configuration: configuration,
            connection: connection,
            viewportDidChange: viewportDidChange
        )
        #elseif canImport(AppKit)
        CanvasRepresentable(
            source: source,
            configuration: configuration,
            connection: connection,
            viewportDidChange: viewportDidChange
        )
        #else
        WatchCanvasView(
            source: source,
            configuration: configuration,
            connection: connection,
            viewportDidChange: viewportDidChange
        )
        #endif
    }
}
