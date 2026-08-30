import CoreGraphics

/// Whether a canvas shows scroll indicators.
public enum CanvasScrollIndicatorVisibility: Equatable, Sendable {
    /// Let the platform decide. This is the default.
    case automatic
    /// Always show indicators while scrolling.
    case visible
    /// Never show indicators.
    case hidden
}

/// How a canvas behaves when panned past its edges.
public enum CanvasBounceBehavior: Equatable, Sendable {
    /// Bounce only along axes whose content overflows the viewport.
    case automatic
    /// Always bounce, even when the content fits.
    case always
    /// Never bounce; the canvas stops hard at its edges.
    case never
}

/// How quickly a canvas coasts to a stop after a fling.
public enum CanvasDecelerationRate: Equatable, Sendable {
    /// A long, gliding coast. The platform default.
    case normal
    /// A short, snappy coast.
    case fast
}
