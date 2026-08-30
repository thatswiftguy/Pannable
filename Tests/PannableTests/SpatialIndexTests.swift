import CoreGraphics
import Testing
@testable import Pannable

/// A deterministic generator, so a failing random case is reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Spatial index")
struct SpatialIndexTests {

    /// The answer the index must reproduce, computed the slow, obviously-correct way.
    private func bruteForce(_ frames: [CGRect], intersecting rect: CGRect) -> [Int] {
        frames.indices.filter { frames[$0].intersects(rect) }.sorted()
    }

    @Test("Queries match a brute-force scan across randomized layouts", arguments: [1, 7, 42, 1_337])
    func matchesBruteForce(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)

        let frames = (0..<600).map { _ in
            CGRect(
                x: CGFloat.random(in: -2000...4000, using: &generator),
                y: CGFloat.random(in: -2000...4000, using: &generator),
                width: CGFloat.random(in: 10...400, using: &generator),
                height: CGFloat.random(in: 10...400, using: &generator)
            )
        }
        let index = SpatialIndex(frames: frames)

        for _ in 0..<200 {
            let query = CGRect(
                x: CGFloat.random(in: -3000...5000, using: &generator),
                y: CGFloat.random(in: -3000...5000, using: &generator),
                width: CGFloat.random(in: 1...1200, using: &generator),
                height: CGFloat.random(in: 1...900, using: &generator)
            )
            #expect(index.indices(intersecting: query) == bruteForce(frames, intersecting: query),
                    "mismatch for query \(query) with seed \(seed)")
        }
    }

    @Test("Widely scattered items stay correct after the grid is coarsened")
    func scatteredItemsRemainQueryable() {
        // Ten million points apart, this would need billions of fine cells; the index
        // coarsens instead of allocating them.
        let frames = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 10_000_000, y: 10_000_000, width: 10, height: 10),
            CGRect(x: 5_000_000, y: 5_000_000, width: 10, height: 10),
        ]
        let index = SpatialIndex(frames: frames)

        #expect(index.indices(intersecting: CGRect(x: -5, y: -5, width: 20, height: 20)) == [0])
        #expect(index.indices(intersecting: CGRect(x: 9_999_995, y: 9_999_995, width: 20, height: 20)) == [1])
        #expect(index.indices(intersecting: CGRect(x: 4_999_995, y: 4_999_995, width: 20, height: 20)) == [2])
    }

    @Test("An item spanning many cells is found from any of them")
    func largeItemIsFoundFromEveryCellItCovers() {
        let frames = [
            CGRect(x: 0, y: 0, width: 20, height: 20),
            CGRect(x: 0, y: 0, width: 5000, height: 5000),
        ]
        let index = SpatialIndex(frames: frames)

        #expect(index.indices(intersecting: CGRect(x: 4900, y: 4900, width: 50, height: 50)) == [1])
        #expect(index.indices(intersecting: CGRect(x: 2000, y: 100, width: 10, height: 10)) == [1])
        #expect(index.indices(intersecting: CGRect(x: 0, y: 0, width: 10, height: 10)) == [0, 1])
    }

    @Test("Results come back in ascending order so hosted views follow the data")
    func resultsAreSortedAscending() {
        let frames = (0..<50).map { CGRect(x: CGFloat($0) * 10, y: 0, width: 100, height: 100) }
        let result = SpatialIndex(frames: frames).indices(intersecting: CGRect(x: 0, y: 0, width: 500, height: 100))
        #expect(result == result.sorted())
        #expect(!result.isEmpty)
    }

    @Test("Rectangles that merely touch are not reported as visible")
    func touchingEdgesDoNotCount() {
        let frames = [CGRect(x: 100, y: 0, width: 100, height: 100)]
        let index = SpatialIndex(frames: frames)

        #expect(index.indices(intersecting: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        #expect(index.indices(intersecting: CGRect(x: 0, y: 0, width: 100.5, height: 100)) == [0])
    }

    @Test("Zero-area and non-finite frames are never reported")
    func degenerateFramesAreIgnored() {
        let frames = [
            CGRect(x: 0, y: 0, width: 0, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 0),
            CGRect(x: CGFloat.nan, y: 0, width: 50, height: 50),
            CGRect(x: 10, y: 10, width: 50, height: 50),
        ]
        let index = SpatialIndex(frames: frames)
        #expect(index.indices(intersecting: CGRect(x: -100, y: -100, width: 400, height: 400)) == [3])
    }

    @Test("An index over nothing answers nothing")
    func emptyIndexReturnsNothing() {
        #expect(SpatialIndex(frames: []).indices(intersecting: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        #expect(SpatialIndex.empty.indices(intersecting: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
    }

    @Test("A query well outside the content finds nothing")
    func queryOutsideContentFindsNothing() {
        let index = SpatialIndex(frames: [CGRect(x: 0, y: 0, width: 100, height: 100)])
        #expect(index.indices(intersecting: CGRect(x: 5000, y: 5000, width: 100, height: 100)).isEmpty)
        #expect(index.indices(intersecting: CGRect(x: -5000, y: -5000, width: 100, height: 100)).isEmpty)
    }

    @Test("An empty query rectangle finds nothing")
    func emptyQueryFindsNothing() {
        let index = SpatialIndex(frames: [CGRect(x: 0, y: 0, width: 100, height: 100)])
        #expect(index.indices(intersecting: .zero).isEmpty)
    }
}
