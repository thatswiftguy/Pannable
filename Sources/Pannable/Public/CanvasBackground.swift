import CoreGraphics
import SwiftUI

/// A repeating pattern drawn behind a canvas's items.
///
/// The backdrop is what makes a canvas read as a canvas rather than as a scroll view:
/// it gives the eye something fixed to the coordinate space to judge movement against.
/// It is drawn as a tiled pattern anchored to the canvas origin, so it costs nothing to
/// pan and nothing in memory no matter how large the canvas is.
///
/// ```swift
/// PannableCanvas(nodes) { NodeCard(node: $0) }
///     .canvasBackground(.dots(spacing: 24))
/// ```
public struct CanvasBackground: Equatable, Sendable {

    @usableFromInline
    enum Pattern: Equatable, Sendable {
        case none
        case dots(spacing: CGFloat, radius: CGFloat)
        case grid(spacing: CGFloat, lineWidth: CGFloat)
    }

    @usableFromInline var pattern: Pattern
    @usableFromInline var color: Color

    @usableFromInline
    init(pattern: Pattern, color: Color) {
        self.pattern = pattern
        self.color = color
    }

    /// No backdrop. The default.
    public static var none: CanvasBackground {
        CanvasBackground(pattern: .none, color: .clear)
    }

    /// A regular field of dots.
    ///
    /// - Parameters:
    ///   - spacing: Distance between dot centres.
    ///   - radius: Radius of each dot.
    ///   - color: Dot colour. Resolves against the current appearance and is redrawn
    ///     when that changes.
    public static func dots(
        spacing: CGFloat = 24,
        radius: CGFloat = 1,
        color: Color = .secondary
    ) -> CanvasBackground {
        CanvasBackground(
            pattern: .dots(spacing: max(1, spacing), radius: max(0.5, radius)),
            color: color
        )
    }

    /// A ruled grid.
    ///
    /// - Parameters:
    ///   - spacing: Distance between lines.
    ///   - lineWidth: Thickness of each line.
    ///   - color: Line colour.
    public static func grid(
        spacing: CGFloat = 40,
        lineWidth: CGFloat = 1,
        color: Color = .secondary
    ) -> CanvasBackground {
        CanvasBackground(
            pattern: .grid(spacing: max(1, spacing), lineWidth: max(0.5, lineWidth)),
            color: color
        )
    }

    /// The edge of one repeating tile, or `nil` when there is nothing to draw.
    var tileSize: CGFloat? {
        switch pattern {
        case .none: return nil
        case .dots(let spacing, _), .grid(let spacing, _): return spacing
        }
    }

    /// One shape making up a tile, in tile-local coordinates.
    enum TileShape: Equatable {
        case ellipse(CGRect)
        case rectangle(CGRect)
    }

    /// The shapes making up one tile.
    ///
    /// The tile repeats from the canvas origin. Both the Core Graphics tiling used on
    /// iOS and macOS and the SwiftUI drawing used on watchOS read the geometry from
    /// here, so the backdrop is identical on every platform.
    func tileShapes(size: CGFloat) -> [TileShape] {
        switch pattern {
        case .none:
            return []

        case .dots(let spacing, let radius):
            // Centring the dot in its tile keeps it whole rather than clipped at the seam.
            return [.ellipse(CGRect(
                x: spacing / 2 - radius,
                y: spacing / 2 - radius,
                width: radius * 2,
                height: radius * 2
            ))]

        case .grid(_, let lineWidth):
            // One horizontal and one vertical edge per tile; neighbours complete the grid.
            return [
                .rectangle(CGRect(x: 0, y: 0, width: size, height: lineWidth)),
                .rectangle(CGRect(x: 0, y: 0, width: lineWidth, height: size)),
            ]
        }
    }

    /// Draws one tile of the pattern into a Core Graphics context.
    func drawTile(in context: CGContext, size: CGFloat, resolvedColor: CGColor) {
        context.setFillColor(resolvedColor)
        for shape in tileShapes(size: size) {
            switch shape {
            case .ellipse(let rect): context.fillEllipse(in: rect)
            case .rectangle(let rect): context.fill(rect)
            }
        }
    }
}

extension View {

    /// Draws a repeating pattern behind the canvas's items.
    ///
    /// ```swift
    /// .canvasBackground(.dots(spacing: 24))
    /// .canvasBackground(.grid(spacing: 40, color: .blue.opacity(0.2)))
    /// ```
    public func canvasBackground(_ background: CanvasBackground) -> some View {
        environment(\.canvasBackground, background)
    }
}
