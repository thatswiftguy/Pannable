import CoreGraphics

/// A type-erased ``CanvasLayout``.
///
/// Use it to switch between layouts that have different types, the way `AnyLayout`
/// works in SwiftUI:
///
/// ```swift
/// .canvasLayout(useGrid ? AnyCanvasLayout(.grid(columns: 6)) : AnyCanvasLayout(.flow))
/// ```
public struct AnyCanvasLayout: CanvasLayout {

    private let base: any CanvasLayout
    private let _place: @Sendable (CanvasLayoutItems, CanvasProposal) -> CanvasLayoutResult

    public init<L: CanvasLayout>(_ layout: L) {
        // Erasing a wrapper again would nest closures for no benefit.
        if let erased = layout as? AnyCanvasLayout {
            self = erased
            return
        }
        self.base = layout
        self._place = { items, proposal in
            var cache = layout.makeCache(itemCount: items.count)
            layout.updateCache(&cache, itemCount: items.count)
            return layout.place(items, in: proposal, cache: &cache)
        }
    }

    public func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
        _place(items, proposal)
    }

    public static func == (lhs: AnyCanvasLayout, rhs: AnyCanvasLayout) -> Bool {
        // Opening the existential recovers the concrete type, so this compares the
        // underlying layouts rather than the erasing boxes.
        func isEqual<L: CanvasLayout>(_ lhsBase: L) -> Bool {
            guard let rhsBase = rhs.base as? L else { return false }
            return lhsBase == rhsBase
        }
        return isEqual(lhs.base)
    }
}
