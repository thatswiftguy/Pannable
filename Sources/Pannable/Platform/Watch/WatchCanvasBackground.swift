#if os(watchOS)

import CoreGraphics
import SwiftUI

/// The canvas backdrop for watchOS.
///
/// There is no pattern colour to lean on here, so the tiles are drawn directly. Only the
/// viewport is ever covered — the pattern is phase-shifted by how far the canvas has
/// been panned, which makes it look anchored to the canvas while costing the same
/// regardless of how large the canvas is.
struct WatchCanvasBackgroundView: View {

    var background: CanvasBackground
    var origin: CGPoint

    var body: some View {
        if let tile = background.tileSize {
            Canvas(opaque: false) { context, size in
                let shapes = background.tileShapes(size: tile)
                guard !shapes.isEmpty else { return }

                // Start one tile before the edge so a partially scrolled tile still
                // draws rather than popping in.
                let startX = -origin.x.truncatingRemainder(dividingBy: tile) - tile
                let startY = -origin.y.truncatingRemainder(dividingBy: tile) - tile

                var y = startY
                while y < size.height {
                    var x = startX
                    while x < size.width {
                        for shape in shapes {
                            let path: Path
                            switch shape {
                            case .ellipse(let rect):
                                path = Path(ellipseIn: rect.offsetBy(dx: x, dy: y))
                            case .rectangle(let rect):
                                path = Path(rect.offsetBy(dx: x, dy: y))
                            }
                            context.fill(path, with: .color(background.color))
                        }
                        x += tile
                    }
                    y += tile
                }
            }
            .allowsHitTesting(false)
        }
    }
}

#endif
