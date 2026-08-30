import CoreGraphics
import SwiftUI
import Testing
@testable import Pannable

/// The tile geometry is shared by the Core Graphics tiling used on iOS and macOS and the
/// SwiftUI drawing used on watchOS, so getting it right here is what keeps the backdrop
/// identical across platforms.
@Suite("Canvas background")
struct CanvasBackgroundTests {

    @Test("No background produces no tile and nothing to draw")
    func noneDrawsNothing() {
        let background = CanvasBackground.none
        #expect(background.tileSize == nil)
        #expect(background.tileShapes(size: 24).isEmpty)
    }

    @Test("A dot sits at the centre of its tile so it is never clipped at the seam")
    func dotIsCentredInTile() {
        let background = CanvasBackground.dots(spacing: 20, radius: 2)
        #expect(background.tileSize == 20)

        #expect(background.tileShapes(size: 20) == [
            .ellipse(CGRect(x: 8, y: 8, width: 4, height: 4))
        ])
    }

    @Test("A grid tile draws one edge on each axis, so neighbours complete the lines")
    func gridDrawsTwoEdges() {
        let background = CanvasBackground.grid(spacing: 40, lineWidth: 2)
        #expect(background.tileSize == 40)

        #expect(background.tileShapes(size: 40) == [
            .rectangle(CGRect(x: 0, y: 0, width: 40, height: 2)),
            .rectangle(CGRect(x: 0, y: 0, width: 2, height: 40)),
        ])
    }

    @Test("Degenerate spacing and line widths are clamped rather than producing an unusable tile")
    func degenerateValuesAreClamped() {
        // A zero or negative spacing would mean an infinite tiling loop on watchOS and a
        // zero-sized pattern image elsewhere.
        #expect(CanvasBackground.dots(spacing: 0).tileSize == 1)
        #expect(CanvasBackground.dots(spacing: -50).tileSize == 1)
        #expect(CanvasBackground.grid(spacing: 0).tileSize == 1)

        let hairline = CanvasBackground.grid(spacing: 10, lineWidth: 0)
        #expect(hairline.tileShapes(size: 10).first == .rectangle(CGRect(x: 0, y: 0, width: 10, height: 0.5)))
    }

    @Test("Backgrounds compare by value, so a host can tell when the backdrop really changed")
    func backgroundsAreValueComparable() {
        #expect(CanvasBackground.dots(spacing: 24) == CanvasBackground.dots(spacing: 24))
        #expect(CanvasBackground.dots(spacing: 24) != CanvasBackground.dots(spacing: 25))
        #expect(CanvasBackground.dots(spacing: 24) != CanvasBackground.grid(spacing: 24))
        #expect(CanvasBackground.dots(spacing: 24, color: .red) != CanvasBackground.dots(spacing: 24, color: .blue))
    }
}
