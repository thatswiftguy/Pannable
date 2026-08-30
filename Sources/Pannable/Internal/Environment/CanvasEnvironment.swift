import CoreGraphics
import SwiftUI

// Canvas configuration travels through the environment rather than through
// initializers, so an ancestor can configure a canvas nested anywhere beneath it —
// the same cascading behavior `.listStyle(_:)` has.

private struct CanvasLayoutKey: EnvironmentKey {
    static let defaultValue = AnyCanvasLayout(FlowCanvasLayout())
}

private struct CanvasContentAnchorKey: EnvironmentKey {
    static let defaultValue = UnitPoint.center
}

private struct CanvasInitialAnchorKey: EnvironmentKey {
    static let defaultValue = UnitPoint.center
}

private struct CanvasContentMarginsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

private struct CanvasItemSizeKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

private struct CanvasEstimatedItemSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 120, height: 120)
}

private struct CanvasScrollIndicatorsKey: EnvironmentKey {
    static let defaultValue = CanvasScrollIndicatorVisibility.automatic
}

private struct CanvasBounceKey: EnvironmentKey {
    static let defaultValue = CanvasBounceBehavior.automatic
}

private struct CanvasScrollDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CanvasDecelerationKey: EnvironmentKey {
    static let defaultValue = CanvasDecelerationRate.normal
}

private struct CanvasOverscanKey: EnvironmentKey {
    static let defaultValue: CGFloat = 128
}

extension EnvironmentValues {
    var canvasLayout: AnyCanvasLayout {
        get { self[CanvasLayoutKey.self] }
        set { self[CanvasLayoutKey.self] = newValue }
    }

    var canvasContentAnchor: UnitPoint {
        get { self[CanvasContentAnchorKey.self] }
        set { self[CanvasContentAnchorKey.self] = newValue }
    }

    var canvasInitialAnchor: UnitPoint {
        get { self[CanvasInitialAnchorKey.self] }
        set { self[CanvasInitialAnchorKey.self] = newValue }
    }

    var canvasContentMargins: EdgeInsets {
        get { self[CanvasContentMarginsKey.self] }
        set { self[CanvasContentMarginsKey.self] = newValue }
    }

    var canvasItemSize: CGSize? {
        get { self[CanvasItemSizeKey.self] }
        set { self[CanvasItemSizeKey.self] = newValue }
    }

    var canvasEstimatedItemSize: CGSize {
        get { self[CanvasEstimatedItemSizeKey.self] }
        set { self[CanvasEstimatedItemSizeKey.self] = newValue }
    }

    var canvasScrollIndicators: CanvasScrollIndicatorVisibility {
        get { self[CanvasScrollIndicatorsKey.self] }
        set { self[CanvasScrollIndicatorsKey.self] = newValue }
    }

    var canvasBounce: CanvasBounceBehavior {
        get { self[CanvasBounceKey.self] }
        set { self[CanvasBounceKey.self] = newValue }
    }

    var canvasScrollDisabled: Bool {
        get { self[CanvasScrollDisabledKey.self] }
        set { self[CanvasScrollDisabledKey.self] = newValue }
    }

    var canvasDeceleration: CanvasDecelerationRate {
        get { self[CanvasDecelerationKey.self] }
        set { self[CanvasDecelerationKey.self] = newValue }
    }

    var canvasOverscan: CGFloat {
        get { self[CanvasOverscanKey.self] }
        set { self[CanvasOverscanKey.self] = newValue }
    }
}
