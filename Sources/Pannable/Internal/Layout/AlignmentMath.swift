import CoreGraphics
import SwiftUI

// SwiftUI's alignment types are opaque handles rather than enums, so they can't be
// switched over. Comparing against the known static members is the supported way to
// interpret them. Baseline alignments carry no meaning without text metrics, so they
// resolve to the nearest edge.

extension HorizontalAlignment {
    /// This alignment as a fraction from leading (0) to trailing (1).
    var canvasUnitValue: CGFloat {
        if self == .leading { return 0 }
        if self == .trailing { return 1 }
        return 0.5
    }
}

extension VerticalAlignment {
    /// This alignment as a fraction from top (0) to bottom (1).
    var canvasUnitValue: CGFloat {
        if self == .top || self == .firstTextBaseline { return 0 }
        if self == .bottom || self == .lastTextBaseline { return 1 }
        return 0.5
    }
}

extension CGRect {
    /// Positions a size of `size` inside this rect at the given unit position.
    func aligning(_ size: CGSize, at unit: CGPoint) -> CGRect {
        CGRect(
            x: minX + (width - size.width) * unit.x,
            y: minY + (height - size.height) * unit.y,
            width: size.width,
            height: size.height
        )
    }
}
