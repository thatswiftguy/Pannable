import CoreGraphics
import SwiftUI

/// Every knob that affects how a canvas lays out and behaves, gathered into one
/// comparable value.
///
/// Hosts re-resolve their layout only when this changes, so an unrelated environment
/// update doesn't cost a full pass over the data.
struct CanvasConfiguration: Equatable {
    var layout: AnyCanvasLayout
    var contentSize: CanvasContentSize
    var contentAnchor: UnitPoint
    var initialAnchor: UnitPoint
    var margins: EdgeInsets
    var itemSize: CGSize?
    var estimatedItemSize: CGSize
    var scrollIndicators: CanvasScrollIndicatorVisibility
    var bounce: CanvasBounceBehavior
    var isScrollDisabled: Bool
    var deceleration: CanvasDecelerationRate
    var overscan: CGFloat
    var background: CanvasBackground
    var layoutDirection: LayoutDirection

    /// Whether a change from `other` invalidates the resolved frames, as opposed to
    /// only affecting how the scroll view behaves.
    func invalidatesLayout(comparedTo other: CanvasConfiguration) -> Bool {
        layout != other.layout
            || contentSize != other.contentSize
            || contentAnchor != other.contentAnchor
            || margins != other.margins
            || itemSize != other.itemSize
            || estimatedItemSize != other.estimatedItemSize
            || layoutDirection != other.layoutDirection
    }
}

extension EnvironmentValues {
    /// The configuration assembled from every canvas modifier in scope.
    var canvasConfiguration: CanvasConfiguration {
        CanvasConfiguration(
            layout: canvasLayout,
            contentSize: .automatic,
            contentAnchor: canvasContentAnchor,
            initialAnchor: canvasInitialAnchor,
            margins: canvasContentMargins,
            itemSize: canvasItemSize,
            estimatedItemSize: canvasEstimatedItemSize,
            scrollIndicators: canvasScrollIndicators,
            bounce: canvasBounce,
            isScrollDisabled: canvasScrollDisabled,
            deceleration: canvasDeceleration,
            overscan: canvasOverscan,
            background: canvasBackground,
            layoutDirection: layoutDirection
        )
    }
}
