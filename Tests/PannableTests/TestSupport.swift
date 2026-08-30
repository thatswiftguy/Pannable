import CoreGraphics
import Testing
@testable import Pannable

/// A layout that hands back frames it was given, so engine tests can exercise
/// anchoring, margins, and mirroring without a real layout's behavior in the way.
struct StubCanvasLayout: CanvasLayout {
    var frames: [CGRect]

    func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
        CanvasLayoutResult(frames: frames)
    }
}

func expectClose(
    _ actual: CGFloat,
    _ expected: CGFloat,
    tolerance: CGFloat = 0.001,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(actual - expected) <= tolerance,
        "expected \(expected), got \(actual)",
        sourceLocation: sourceLocation
    )
}

func expectClose(
    _ actual: CGRect,
    _ expected: CGRect,
    tolerance: CGFloat = 0.001,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let matches = abs(actual.minX - expected.minX) <= tolerance
        && abs(actual.minY - expected.minY) <= tolerance
        && abs(actual.width - expected.width) <= tolerance
        && abs(actual.height - expected.height) <= tolerance
    #expect(matches, "expected \(expected), got \(actual)", sourceLocation: sourceLocation)
}

func expectClose(
    _ actual: CGSize,
    _ expected: CGSize,
    tolerance: CGFloat = 0.001,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let matches = abs(actual.width - expected.width) <= tolerance
        && abs(actual.height - expected.height) <= tolerance
    #expect(matches, "expected \(expected), got \(actual)", sourceLocation: sourceLocation)
}

extension CGSize {
    static func square(_ side: CGFloat) -> CGSize { CGSize(width: side, height: side) }
}
