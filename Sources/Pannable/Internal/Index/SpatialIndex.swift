import CoreGraphics

/// A uniform-grid index over item frames, answering "what is inside this rectangle?"
///
/// Every pan event needs the set of items intersecting the viewport. Scanning all
/// frames would make scrolling cost O(items) per frame — fine at a hundred items,
/// ruinous at ten thousand. Bucketing frames into a coarse grid makes the query cost
/// proportional to the visible area instead of to the data size.
struct SpatialIndex: Sendable {

    /// Cell edges are kept in this range: small enough that a query touches few cells,
    /// large enough that a big item isn't registered in hundreds of buckets.
    private static let minimumCellExtent: CGFloat = 64
    private static let maximumCellExtent: CGFloat = 2048

    /// Ceiling on total buckets, so a sparse canvas with far-flung items can't allocate
    /// an enormous grid.
    private static let maximumCellCount = 65_536

    private let frames: [CGRect]
    private let origin: CGPoint
    private let cellSize: CGSize
    private let columns: Int
    private let rows: Int
    private let buckets: [[Int]]

    /// An index over no items.
    static let empty = SpatialIndex(frames: [])

    init(frames: [CGRect]) {
        self.frames = frames

        let positioned = frames.filter { $0.isFinite && !$0.isEmpty }
        guard !positioned.isEmpty else {
            self.origin = .zero
            self.cellSize = CGSize(width: Self.minimumCellExtent, height: Self.minimumCellExtent)
            self.columns = 0
            self.rows = 0
            self.buckets = []
            return
        }

        let bounds = positioned.reduce(CGRect.null) { $0.union($1) }

        // Sizing cells off the typical item keeps the average item in one or two
        // buckets. The median resists a handful of outsized items skewing the grid.
        var cellWidth = Self.clampExtent(Self.median(of: positioned.map(\.width)) * 2)
        var cellHeight = Self.clampExtent(Self.median(of: positioned.map(\.height)) * 2)

        var columnCount = Self.cellCount(spanning: bounds.width, cellExtent: cellWidth)
        var rowCount = Self.cellCount(spanning: bounds.height, cellExtent: cellHeight)

        // Widely scattered items make for a mostly empty grid; coarsen it until the
        // bucket count is sane.
        if columnCount * rowCount > Self.maximumCellCount {
            let overshoot = (CGFloat(columnCount) * CGFloat(rowCount) / CGFloat(Self.maximumCellCount)).squareRoot()
            cellWidth *= overshoot
            cellHeight *= overshoot
            columnCount = Self.cellCount(spanning: bounds.width, cellExtent: cellWidth)
            rowCount = Self.cellCount(spanning: bounds.height, cellExtent: cellHeight)
        }

        self.origin = bounds.origin
        self.cellSize = CGSize(width: cellWidth, height: cellHeight)
        self.columns = columnCount
        self.rows = rowCount

        var buckets = [[Int]](repeating: [], count: columnCount * rowCount)
        for (index, frame) in frames.enumerated() where frame.isFinite && !frame.isEmpty {
            let span = Self.cellSpan(
                for: frame,
                origin: bounds.origin,
                cellSize: CGSize(width: cellWidth, height: cellHeight),
                columns: columnCount,
                rows: rowCount
            )
            guard let span else { continue }
            for row in span.rows {
                let rowOffset = row * columnCount
                for column in span.columns {
                    buckets[rowOffset + column].append(index)
                }
            }
        }
        self.buckets = buckets
    }

    /// The indices of every item whose frame intersects `rect`, in ascending order.
    ///
    /// Ordering is ascending rather than bucket order so that hosted views stay in the
    /// data's own sequence — which is what VoiceOver reads out.
    func indices(intersecting rect: CGRect) -> [Int] {
        guard columns > 0, rows > 0, rect.isFinite, !rect.isEmpty else { return [] }

        let span = Self.cellSpan(for: rect, origin: origin, cellSize: cellSize, columns: columns, rows: rows)
        guard let span else { return [] }

        // An item spanning several cells appears in each, so candidates need deduping
        // before the exact test.
        var candidates = Set<Int>()
        for row in span.rows {
            let rowOffset = row * columns
            for column in span.columns {
                candidates.formUnion(buckets[rowOffset + column])
            }
        }

        return candidates.filter { frames[$0].intersects(rect) }.sorted()
    }

    // MARK: - Grid math

    private struct CellSpan {
        var columns: ClosedRange<Int>
        var rows: ClosedRange<Int>
    }

    /// The block of cells `rect` covers, or `nil` when it falls entirely outside the grid.
    private static func cellSpan(
        for rect: CGRect,
        origin: CGPoint,
        cellSize: CGSize,
        columns: Int,
        rows: Int
    ) -> CellSpan? {
        let minColumn = Int(((rect.minX - origin.x) / cellSize.width).rounded(.down))
        let maxColumn = Int(((rect.maxX - origin.x) / cellSize.width).rounded(.down))
        let minRow = Int(((rect.minY - origin.y) / cellSize.height).rounded(.down))
        let maxRow = Int(((rect.maxY - origin.y) / cellSize.height).rounded(.down))

        guard maxColumn >= 0, minColumn <= columns - 1, maxRow >= 0, minRow <= rows - 1 else {
            return nil
        }

        return CellSpan(
            columns: max(0, minColumn)...min(columns - 1, maxColumn),
            rows: max(0, minRow)...min(rows - 1, maxRow)
        )
    }

    private static func cellCount(spanning extent: CGFloat, cellExtent: CGFloat) -> Int {
        guard extent.isFinite, extent > 0, cellExtent > 0 else { return 1 }
        return max(1, Int((extent / cellExtent).rounded(.up)))
    }

    private static func clampExtent(_ extent: CGFloat) -> CGFloat {
        guard extent.isFinite, extent > 0 else { return minimumCellExtent }
        return min(max(extent, minimumCellExtent), maximumCellExtent)
    }

    private static func median(of values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

extension CGRect {
    /// Whether every component of this rect is a finite number.
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}
