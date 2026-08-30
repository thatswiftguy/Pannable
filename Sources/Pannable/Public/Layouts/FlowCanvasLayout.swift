import CoreGraphics
import SwiftUI

/// A layout that fills rows left to right, wrapping to a new row when the next
/// item would overflow the available width.
///
/// Rows are only as tall as their tallest item, so items of mixed heights pack
/// tightly rather than being forced onto a uniform grid.
///
/// Build one with ``CanvasLayout/flow(horizontalSpacing:verticalSpacing:alignment:maxWidth:)``.
public struct FlowCanvasLayout: CanvasLayout {

    /// Space between items within a row.
    public var horizontalSpacing: CGFloat

    /// Space between rows.
    public var verticalSpacing: CGFloat

    /// How items shorter than their row are positioned within it.
    public var alignment: VerticalAlignment

    /// A hard wrapping width, overriding whatever the canvas proposes.
    public var maxWidth: CGFloat?

    public init(
        horizontalSpacing: CGFloat = 8,
        verticalSpacing: CGFloat = 8,
        alignment: VerticalAlignment = .center,
        maxWidth: CGFloat? = nil
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.alignment = alignment
        self.maxWidth = maxWidth
    }

    public func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
        guard !items.isEmpty else { return CanvasLayoutResult(frames: []) }

        let wrappingWidth = resolvedWrappingWidth(for: items, proposal: proposal)
        let verticalUnit = alignment.canvasUnitValue

        var frames = [CGRect](repeating: .zero, count: items.count)
        var rowPositions: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var y: CGFloat = 0

        // Commits the pending row: every item in it is aligned against the row's
        // final height, which is only known once the row is closed.
        func flushRow() {
            var x: CGFloat = 0
            for position in rowPositions {
                let size = items[position].size
                let rowRect = CGRect(x: x, y: y, width: size.width, height: rowHeight)
                frames[position] = rowRect.aligning(size, at: CGPoint(x: 0, y: verticalUnit))
                x += size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
            rowPositions.removeAll(keepingCapacity: true)
            rowWidth = 0
            rowHeight = 0
        }

        for (position, item) in items.enumerated() {
            let size = item.size
            let widthIfAppended = rowPositions.isEmpty ? size.width : rowWidth + horizontalSpacing + size.width

            // A lone item wider than the wrapping width still gets its own row rather
            // than an empty one followed by an overflowing one.
            if !rowPositions.isEmpty && widthIfAppended > wrappingWidth {
                flushRow()
            }

            rowWidth = rowPositions.isEmpty ? size.width : rowWidth + horizontalSpacing + size.width
            rowHeight = max(rowHeight, size.height)
            rowPositions.append(position)
        }

        if !rowPositions.isEmpty { flushRow() }

        return CanvasLayoutResult(frames: frames)
    }

    /// Picks the width rows wrap at.
    ///
    /// An explicit `maxWidth` wins, then whatever the canvas proposes. With neither —
    /// which is what ``CanvasContentSize/automatic`` produces — the items would
    /// otherwise land in one endless row, so aim for a roughly square cluster instead.
    private func resolvedWrappingWidth(for items: CanvasLayoutItems, proposal: CanvasProposal) -> CGFloat {
        let widest = items.lazy.map(\.size.width).max() ?? 0

        if let maxWidth {
            return max(maxWidth, widest)
        }
        if let proposed = proposal.width, proposed > 0 {
            return max(proposed, widest)
        }

        let totalArea = items.reduce(CGFloat.zero) { partial, item in
            partial + (item.size.width + horizontalSpacing) * (item.size.height + verticalSpacing)
        }
        return max(totalArea.squareRoot(), widest)
    }
}

extension CanvasLayout where Self == FlowCanvasLayout {

    /// A flow layout with default spacing.
    public static var flow: FlowCanvasLayout { FlowCanvasLayout() }

    /// A layout that fills rows left to right, wrapping when a row runs out of width.
    ///
    /// - Parameters:
    ///   - horizontalSpacing: Space between items within a row.
    ///   - verticalSpacing: Space between rows.
    ///   - alignment: How items shorter than their row sit within it.
    ///   - maxWidth: A hard wrapping width. When `nil`, the canvas's own width is used.
    public static func flow(
        horizontalSpacing: CGFloat = 8,
        verticalSpacing: CGFloat = 8,
        alignment: VerticalAlignment = .center,
        maxWidth: CGFloat? = nil
    ) -> FlowCanvasLayout {
        FlowCanvasLayout(
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            alignment: alignment,
            maxWidth: maxWidth
        )
    }
}
