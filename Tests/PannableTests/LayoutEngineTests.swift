import CoreGraphics
import SwiftUI
import Testing
@testable import Pannable

@Suite("Layout engine")
struct LayoutEngineTests {

    /// A 100x100 cluster made of one item, on a 1000x1000 canvas: 900 points of slack
    /// on each axis, so anchoring is easy to read off the result.
    private func resolveSingleItem(
        anchor: UnitPoint,
        margins: EdgeInsets = EdgeInsets(),
        contentSize: CanvasContentSize = .fixed(width: 1000, height: 1000),
        layoutDirection: LayoutDirection = .leftToRight
    ) -> CanvasResolution {
        LayoutEngine.resolve(
            sizes: [.square(100)],
            layout: StubCanvasLayout(frames: [CGRect(x: 0, y: 0, width: 100, height: 100)]),
            contentSize: contentSize,
            margins: margins,
            contentAnchor: anchor,
            layoutDirection: layoutDirection
        )
    }

    @Test("Every unit point anchors the cluster where it says", arguments: [
        (UnitPoint.topLeading, CGPoint(x: 0, y: 0)),
        (.top, CGPoint(x: 450, y: 0)),
        (.topTrailing, CGPoint(x: 900, y: 0)),
        (.leading, CGPoint(x: 0, y: 450)),
        (.center, CGPoint(x: 450, y: 450)),
        (.trailing, CGPoint(x: 900, y: 450)),
        (.bottomLeading, CGPoint(x: 0, y: 900)),
        (.bottom, CGPoint(x: 450, y: 900)),
        (.bottomTrailing, CGPoint(x: 900, y: 900)),
    ])
    func anchoring(anchor: UnitPoint, expectedOrigin: CGPoint) {
        let result = resolveSingleItem(anchor: anchor)
        expectClose(result.frames[0], CGRect(origin: expectedOrigin, size: .square(100)))
    }

    @Test("Margins inset the box the cluster is anchored inside")
    func marginsInsetTheAnchorBox() {
        let margins = EdgeInsets(top: 50, leading: 20, bottom: 10, trailing: 100)
        let result = resolveSingleItem(anchor: .topLeading, margins: margins)
        expectClose(result.frames[0], CGRect(x: 20, y: 50, width: 100, height: 100))

        let trailing = resolveSingleItem(anchor: .bottomTrailing, margins: margins)
        // Available box is 880x940 at (20, 50); the item sits at its far corner.
        expectClose(trailing.frames[0], CGRect(x: 800, y: 890, width: 100, height: 100))
    }

    @Test("A layout placing items at negative coordinates is normalized before anchoring")
    func negativeCoordinatesAreNormalized() {
        let result = LayoutEngine.resolve(
            sizes: [.square(100), .square(100)],
            layout: StubCanvasLayout(frames: [
                CGRect(x: -300, y: -300, width: 100, height: 100),
                CGRect(x: -100, y: -100, width: 100, height: 100),
            ]),
            contentSize: .fixed(width: 1000, height: 1000),
            margins: EdgeInsets(),
            contentAnchor: .topLeading
        )
        // The cluster spans 300x300 from (-300,-300); shifted to the origin it becomes
        // (0,0) and (200,200).
        expectClose(result.frames[0], CGRect(x: 0, y: 0, width: 100, height: 100))
        expectClose(result.frames[1], CGRect(x: 200, y: 200, width: 100, height: 100))
        expectClose(result.contentBounds, CGRect(x: 0, y: 0, width: 300, height: 300))
    }

    @Test("Automatic content size hugs the cluster plus margins")
    func automaticContentSizeHugsContent() {
        let result = LayoutEngine.resolve(
            sizes: [.square(100), .square(100)],
            layout: StubCanvasLayout(frames: [
                CGRect(x: 0, y: 0, width: 100, height: 100),
                CGRect(x: 300, y: 150, width: 100, height: 100),
            ]),
            contentSize: .automatic,
            margins: EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40),
            contentAnchor: .center
        )
        // Cluster is 400x250; margins add 60 wide and 40 tall.
        expectClose(result.contentSize, CGSize(width: 460, height: 290))
        // With no slack, the anchor has nothing to do and the cluster sits at the margin.
        expectClose(result.frames[0], CGRect(x: 20, y: 10, width: 100, height: 100))
    }

    @Test("Fixed content size is honored exactly")
    func fixedContentSizeIsExact() {
        let result = resolveSingleItem(anchor: .center, contentSize: .fixed(width: 4000, height: 3000))
        expectClose(result.contentSize, CGSize(width: 4000, height: 3000))
    }

    @Test("atLeast grows past its floor only when the content needs it")
    func atLeastGrowsToFitContent() {
        let small = LayoutEngine.resolve(
            sizes: [.square(100)],
            layout: StubCanvasLayout(frames: [CGRect(x: 0, y: 0, width: 100, height: 100)]),
            contentSize: .atLeast(width: 500, height: 500),
            margins: EdgeInsets(),
            contentAnchor: .topLeading
        )
        expectClose(small.contentSize, CGSize(width: 500, height: 500))

        let large = LayoutEngine.resolve(
            sizes: [CGSize(width: 900, height: 100)],
            layout: StubCanvasLayout(frames: [CGRect(x: 0, y: 0, width: 900, height: 100)]),
            contentSize: .atLeast(width: 500, height: 500),
            margins: EdgeInsets(),
            contentAnchor: .topLeading
        )
        expectClose(large.contentSize, CGSize(width: 900, height: 500))
    }

    @Test("Content overflowing a fixed canvas is pinned to the leading margin, not centered off-canvas")
    func overflowIsPinnedRatherThanClippedOnAllSides() {
        let result = LayoutEngine.resolve(
            sizes: [CGSize(width: 2000, height: 2000)],
            layout: StubCanvasLayout(frames: [CGRect(x: 0, y: 0, width: 2000, height: 2000)]),
            contentSize: .fixed(width: 1000, height: 1000),
            margins: EdgeInsets(top: 25, leading: 25, bottom: 25, trailing: 25),
            contentAnchor: .center
        )
        // Centering a 2000pt cluster in a 950pt box would start it at -525, putting the
        // top-left beyond where panning can reach. It pins to the margin instead.
        expectClose(result.frames[0], CGRect(x: 25, y: 25, width: 2000, height: 2000))
    }

    @Test("Right-to-left mirrors the cluster and flips the anchor")
    func rightToLeftMirrorsLayout() {
        let result = LayoutEngine.resolve(
            sizes: [.square(100), .square(100)],
            layout: StubCanvasLayout(frames: [
                CGRect(x: 0, y: 0, width: 100, height: 100),
                CGRect(x: 200, y: 0, width: 100, height: 100),
            ]),
            contentSize: .fixed(width: 1000, height: 1000),
            margins: EdgeInsets(),
            contentAnchor: .topLeading,
            layoutDirection: .rightToLeft
        )
        // topLeading becomes top-right, and the first item stays visually first — which
        // in RTL means rightmost.
        expectClose(result.frames[0], CGRect(x: 900, y: 0, width: 100, height: 100))
        expectClose(result.frames[1], CGRect(x: 700, y: 0, width: 100, height: 100))
    }

    @Test("Right-to-left swaps which side the leading margin insets")
    func rightToLeftSwapsMarginSides() {
        let result = resolveSingleItem(
            anchor: .topLeading,
            margins: EdgeInsets(top: 0, leading: 30, bottom: 0, trailing: 70),
            layoutDirection: .rightToLeft
        )
        // The leading margin is now on the right, so the item stops 30pt short of 1000.
        expectClose(result.frames[0].maxX, 970)
    }

    @Test("A sized canvas proposes its size minus margins; automatic proposes nothing")
    func proposalReflectsContentSize() {
        let fixed = LayoutEngine.proposal(
            for: .fixed(width: 1000, height: 800),
            horizontalInsets: 60,
            verticalInsets: 40
        )
        #expect(fixed.width == 940)
        #expect(fixed.height == 760)

        // A floor still gives the layout a width to wrap against.
        let atLeast = LayoutEngine.proposal(for: .atLeast(width: 500, height: 500), horizontalInsets: 0, verticalInsets: 0)
        #expect(atLeast.width == 500)

        let automatic = LayoutEngine.proposal(for: .automatic, horizontalInsets: 0, verticalInsets: 0)
        #expect(automatic.width == nil)
        #expect(automatic.height == nil)

        // Margins wider than the canvas must not propose a negative width.
        let overInset = LayoutEngine.proposal(for: .fixed(width: 100, height: 100), horizontalInsets: 500, verticalInsets: 500)
        #expect(overInset.width == 0)
        #expect(overInset.height == 0)
    }

    @Test("Non-finite and negative measurements are neutralized")
    func nonFiniteSizesAreSanitized() {
        let result = LayoutEngine.resolve(
            sizes: [CGSize(width: CGFloat.nan, height: 50), CGSize(width: -20, height: CGFloat.infinity)],
            layout: GridCanvasLayout(columns: 2, horizontalSpacing: 0, verticalSpacing: 0),
            contentSize: .automatic,
            margins: EdgeInsets(),
            contentAnchor: .topLeading
        )
        #expect(result.frames.allSatisfy { $0.isFinite })
        #expect(result.contentSize.width.isFinite)
        #expect(result.contentSize.height.isFinite)
    }

    @Test("An empty canvas still resolves its declared size")
    func emptyDataStillResolvesContentSize() {
        let result = LayoutEngine.resolve(
            sizes: [],
            layout: FlowCanvasLayout(),
            contentSize: .fixed(width: 640, height: 480),
            margins: EdgeInsets(),
            contentAnchor: .center
        )
        #expect(result.frames.isEmpty)
        expectClose(result.contentSize, CGSize(width: 640, height: 480))
    }
}
