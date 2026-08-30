import CoreGraphics
import SwiftUI
import Testing
@testable import Pannable

@Suite("Flow layout")
struct FlowCanvasLayoutTests {

    private func place(
        _ sizes: [CGSize],
        layout: FlowCanvasLayout,
        proposal: CanvasProposal
    ) -> [CGRect] {
        var cache = layout.makeCache(itemCount: sizes.count)
        return layout.place(CanvasLayoutItems(sizes: sizes), in: proposal, cache: &cache).frames
    }

    @Test("Rows wrap once the next item would overflow the proposed width")
    func rowsWrapAtProposedWidth() {
        let layout = FlowCanvasLayout(horizontalSpacing: 10, verticalSpacing: 20, alignment: .top)
        // Three 100pt items with 10pt gaps need 320pt; only two fit in 250.
        let frames = place(Array(repeating: .square(100), count: 3), layout: layout, proposal: CanvasProposal(width: 250, height: nil))

        expectClose(frames[0], CGRect(x: 0, y: 0, width: 100, height: 100))
        expectClose(frames[1], CGRect(x: 110, y: 0, width: 100, height: 100))
        expectClose(frames[2], CGRect(x: 0, y: 120, width: 100, height: 100))
    }

    @Test("A row is as tall as its tallest item")
    func rowHeightFollowsTallestItem() {
        let layout = FlowCanvasLayout(horizontalSpacing: 0, verticalSpacing: 0, alignment: .top)
        let frames = place(
            [CGSize(width: 50, height: 30), CGSize(width: 50, height: 90), CGSize(width: 50, height: 20)],
            layout: layout,
            proposal: CanvasProposal(width: 100, height: nil)
        )
        // First row holds two items and is 90 tall, so the third starts at y = 90.
        expectClose(frames[2].minY, 90)
    }

    @Test("Vertical alignment positions short items within their row", arguments: [
        (VerticalAlignment.top, CGFloat(0)),
        (.center, 30),
        (.bottom, 60),
    ])
    func verticalAlignmentWithinRow(alignment: VerticalAlignment, expectedY: CGFloat) {
        let layout = FlowCanvasLayout(horizontalSpacing: 0, verticalSpacing: 0, alignment: alignment)
        let frames = place(
            [CGSize(width: 50, height: 100), CGSize(width: 50, height: 40)],
            layout: layout,
            proposal: CanvasProposal(width: 100, height: nil)
        )
        expectClose(frames[1].minY, expectedY)
    }

    @Test("An item wider than the wrapping width gets its own row rather than an empty one")
    func oversizedItemDoesNotProduceAnEmptyRow() {
        let layout = FlowCanvasLayout(horizontalSpacing: 10, verticalSpacing: 10, alignment: .top)
        let frames = place(
            [CGSize(width: 500, height: 50), CGSize(width: 40, height: 50)],
            layout: layout,
            proposal: CanvasProposal(width: 100, height: nil)
        )
        expectClose(frames[0], CGRect(x: 0, y: 0, width: 500, height: 50))
        expectClose(frames[1], CGRect(x: 0, y: 60, width: 40, height: 50))
    }

    @Test("An explicit maxWidth overrides whatever the canvas proposes")
    func maxWidthOverridesProposal() {
        let layout = FlowCanvasLayout(horizontalSpacing: 0, verticalSpacing: 0, alignment: .top, maxWidth: 100)
        let frames = place(Array(repeating: .square(60), count: 2), layout: layout, proposal: CanvasProposal(width: 1000, height: nil))
        // 1000pt was proposed but maxWidth caps the row at 100, so the second wraps.
        expectClose(frames[1], CGRect(x: 0, y: 60, width: 60, height: 60))
    }

    @Test("With no proposed width the cluster stays roughly square instead of one endless row")
    func unboundedWidthProducesSquareCluster() {
        let layout = FlowCanvasLayout(horizontalSpacing: 0, verticalSpacing: 0, alignment: .top)
        let frames = place(Array(repeating: .square(100), count: 100), layout: layout, proposal: .unspecified)
        let bounds = CanvasLayoutResult(frames: frames).bounds

        #expect(bounds.width < 2000, "an unbounded flow must not degenerate into a single row")
        let aspect = bounds.width / bounds.height
        #expect(aspect > 0.5 && aspect < 2.0, "expected a roughly square cluster, got aspect \(aspect)")
    }

    @Test("No items produces no frames")
    func emptyInputProducesNoFrames() {
        let frames = place([], layout: FlowCanvasLayout(), proposal: CanvasProposal(width: 500, height: nil))
        #expect(frames.isEmpty)
    }
}

@Suite("Grid layout")
struct GridCanvasLayoutTests {

    private func place(_ sizes: [CGSize], layout: GridCanvasLayout) -> [CGRect] {
        var cache = layout.makeCache(itemCount: sizes.count)
        return layout.place(CanvasLayoutItems(sizes: sizes), in: .unspecified, cache: &cache).frames
    }

    @Test("Items fill rows across the requested number of columns")
    func itemsFillRowsAcrossColumns() {
        let layout = GridCanvasLayout(columns: 3, horizontalSpacing: 10, verticalSpacing: 10)
        let frames = place(Array(repeating: .square(50), count: 7), layout: layout)

        expectClose(frames[0], CGRect(x: 0, y: 0, width: 50, height: 50))
        expectClose(frames[2], CGRect(x: 120, y: 0, width: 50, height: 50))
        expectClose(frames[3], CGRect(x: 0, y: 60, width: 50, height: 50))
        // Seven items over three columns leaves a partial final row.
        expectClose(frames[6], CGRect(x: 0, y: 120, width: 50, height: 50))
    }

    @Test("A column is as wide as its widest item and a row as tall as its tallest")
    func cellsSizeToTheirWidestAndTallestMember() {
        let layout = GridCanvasLayout(columns: 2, horizontalSpacing: 0, verticalSpacing: 0, alignment: .topLeading)
        let frames = place([
            CGSize(width: 30, height: 10),
            CGSize(width: 20, height: 80),
            CGSize(width: 90, height: 10),
            CGSize(width: 20, height: 10),
        ], layout: layout)

        // Column 0 is 90 wide (item 2), so column 1 starts at x = 90.
        expectClose(frames[1].minX, 90)
        // Row 0 is 80 tall (item 1), so row 1 starts at y = 80.
        expectClose(frames[2].minY, 80)
    }

    @Test("Alignment positions an item inside its cell", arguments: [
        (Alignment.topLeading, CGPoint(x: 0, y: 0)),
        (.center, CGPoint(x: 20, y: 20)),
        (.bottomTrailing, CGPoint(x: 40, y: 40)),
    ])
    func alignmentWithinCell(alignment: Alignment, expectedOrigin: CGPoint) {
        let layout = GridCanvasLayout(columns: 2, horizontalSpacing: 0, verticalSpacing: 0, alignment: alignment)
        // Item 1 makes row 0 100 tall and item 2 makes column 0 100 wide, so item 0 sits
        // in a 100x100 cell with 40pt of slack on both axes.
        let frames = place([
            .square(60),
            CGSize(width: 20, height: 100),
            CGSize(width: 100, height: 20),
        ], layout: layout)
        expectClose(frames[0].origin.x, expectedOrigin.x)
        expectClose(frames[0].origin.y, expectedOrigin.y)
    }

    @Test("A column count below one is treated as a single column")
    func columnCountIsClampedToAtLeastOne() {
        let frames = place(Array(repeating: .square(10), count: 3), layout: GridCanvasLayout(columns: 0, horizontalSpacing: 0, verticalSpacing: 0))
        #expect(frames.map(\.minX).allSatisfy { $0 == 0 })
        expectClose(frames[2].minY, 20)
    }

    @Test("No items produces no frames")
    func emptyInputProducesNoFrames() {
        #expect(place([], layout: GridCanvasLayout(columns: 4)).isEmpty)
    }
}
