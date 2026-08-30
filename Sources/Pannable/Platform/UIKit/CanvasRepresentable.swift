#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

/// Bridges the UIKit canvas into SwiftUI.
///
/// This vends a view controller rather than a bare view because every item on the
/// canvas is itself a `UIHostingController`, and those need a parent to be contained
/// by — without proper containment their trait collection, safe area, and appearance
/// callbacks are all subtly wrong.
struct CanvasRepresentable<Content: View>: UIViewControllerRepresentable {

    var source: CanvasItemSource<Content>
    var configuration: CanvasConfiguration
    var connection: CanvasConnection?
    var viewportDidChange: (CanvasViewport) -> Void

    func makeUIViewController(context: Context) -> CanvasViewController<Content> {
        let controller = CanvasViewController(source: source, configuration: configuration)
        controller.viewportDidChange = viewportDidChange
        controller.connection = connection
        return controller
    }

    func updateUIViewController(_ controller: CanvasViewController<Content>, context: Context) {
        controller.viewportDidChange = viewportDidChange
        if controller.connection !== connection {
            controller.connection = connection
        }
        controller.update(source: source, configuration: configuration)
    }
}

#endif
