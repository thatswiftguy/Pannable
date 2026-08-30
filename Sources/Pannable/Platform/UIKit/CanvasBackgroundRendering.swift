#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

extension CanvasBackground {

    /// The backdrop as a tiling pattern colour, or `nil` when there is nothing to draw.
    ///
    /// A pattern colour is what makes an arbitrarily large canvas affordable. Drawing
    /// the backdrop into the content view directly would demand a backing store for the
    /// whole canvas — a 6000×6000 canvas at 3× is over a gigabyte — whereas a pattern
    /// repeats one small tile with no per-canvas cost at all.
    func patternColor(for traitCollection: UITraitCollection) -> UIColor? {
        guard let tileSize else { return nil }

        let resolved = UIColor(color).resolvedColor(with: traitCollection).cgColor
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        format.scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : UIScreen.main.scale

        let tile = CGSize(width: tileSize, height: tileSize)
        let image = UIGraphicsImageRenderer(size: tile, format: format).image { context in
            drawTile(in: context.cgContext, size: tileSize, resolvedColor: resolved)
        }
        return UIColor(patternImage: image)
    }
}

#endif
