#if os(macOS)

import AppKit
import SwiftUI

extension CanvasBackground {

    /// The backdrop as a tiling pattern colour, or `nil` when there is nothing to draw.
    ///
    /// Tiling one small image keeps an arbitrarily large canvas free of any per-canvas
    /// drawing cost.
    func patternColor(for appearance: NSAppearance) -> NSColor? {
        guard let tileSize else { return nil }

        var resolved: CGColor?
        // Colours such as `.secondary` are appearance-dependent, so they must resolve
        // against the view's appearance rather than whatever is current.
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).cgColor
        }
        guard let resolved else { return nil }

        let tile = NSSize(width: tileSize, height: tileSize)
        let image = NSImage(size: tile, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            self.drawTile(in: context, size: tileSize, resolvedColor: resolved)
            return true
        }
        return NSColor(patternImage: image)
    }
}

#endif
