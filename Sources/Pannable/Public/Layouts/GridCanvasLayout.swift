import CoreGraphics
import SwiftUI

/// A layout that arranges items into a fixed number of columns.
///
/// Each column is as wide as its widest item and each row as tall as its tallest,
/// matching how SwiftUI's `Grid` sizes its cells. Items smaller than their cell are
/// positioned by `alignment`.
///
/// Build one with ``CanvasLayout/grid(columns:horizontalSpacing:verticalSpacing:alignment:)``.
public struct GridCanvasLayout: CanvasLayout {

    /// The number of columns. Always at least one.
    public var columns: Int

    /// Space between columns.
    public var horizontalSpacing: CGFloat

    /// Space between rows.
    public var verticalSpacing: CGFloat

    /// How an item smaller than its cell is positioned within it.
    public var alignment: Alignment

    public init(
        columns: Int,
        horizontalSpacing: CGFloat = 8,
        verticalSpacing: CGFloat = 8,
        alignment: Alignment = .center
    ) {
        self.columns = max(1, columns)
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.alignment = alignment
    }

    public func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
        guard !items.isEmpty else { return CanvasLayoutResult(frames: []) }

        let columnCount = max(1, columns)
        let rowCount = (items.count + columnCount - 1) / columnCount

        // Cells size to the largest item sharing their column or row.
        var columnWidths = [CGFloat](repeating: 0, count: columnCount)
        var rowHeights = [CGFloat](repeating: 0, count: rowCount)

        for (offset, item) in items.enumerated() {
            let column = offset % columnCount
            let row = offset / columnCount
            columnWidths[column] = max(columnWidths[column], item.size.width)
            rowHeights[row] = max(rowHeights[row], item.size.height)
        }

        // Running offsets, so each cell's origin is a lookup rather than a re-sum.
        var columnOffsets = [CGFloat](repeating: 0, count: columnCount)
        var x: CGFloat = 0
        for column in 0..<columnCount {
            columnOffsets[column] = x
            x += columnWidths[column] + horizontalSpacing
        }

        var rowOffsets = [CGFloat](repeating: 0, count: rowCount)
        var y: CGFloat = 0
        for row in 0..<rowCount {
            rowOffsets[row] = y
            y += rowHeights[row] + verticalSpacing
        }

        let unit = CGPoint(
            x: alignment.horizontal.canvasUnitValue,
            y: alignment.vertical.canvasUnitValue
        )

        var frames = [CGRect](repeating: .zero, count: items.count)
        for (offset, item) in items.enumerated() {
            let column = offset % columnCount
            let row = offset / columnCount
            let cell = CGRect(
                x: columnOffsets[column],
                y: rowOffsets[row],
                width: columnWidths[column],
                height: rowHeights[row]
            )
            frames[offset] = cell.aligning(item.size, at: unit)
        }

        return CanvasLayoutResult(frames: frames)
    }
}

extension CanvasLayout where Self == GridCanvasLayout {

    /// A layout that arranges items into a fixed number of columns.
    ///
    /// - Parameters:
    ///   - columns: How many columns to fill. Values below one are treated as one.
    ///   - horizontalSpacing: Space between columns.
    ///   - verticalSpacing: Space between rows.
    ///   - alignment: How an item smaller than its cell sits within it.
    public static func grid(
        columns: Int,
        horizontalSpacing: CGFloat = 8,
        verticalSpacing: CGFloat = 8,
        alignment: Alignment = .center
    ) -> GridCanvasLayout {
        GridCanvasLayout(
            columns: columns,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            alignment: alignment
        )
    }
}
