#if os(macOS)

import AppKit
import SwiftUI

/// Bridges the AppKit canvas into SwiftUI.
///
/// A view controller rather than a bare view, because every item is an
/// `NSHostingController` and those need a parent to be contained by.
struct CanvasRepresentable<Content: View>: NSViewControllerRepresentable {

    var source: CanvasItemSource<Content>
    var configuration: CanvasConfiguration
    var connection: CanvasConnection?
    var viewportDidChange: (CanvasViewport) -> Void

    func makeNSViewController(context: Context) -> CanvasViewController<Content> {
        let controller = CanvasViewController(source: source, configuration: configuration)
        controller.viewportDidChange = viewportDidChange
        controller.connection = connection
        return controller
    }

    func updateNSViewController(_ controller: CanvasViewController<Content>, context: Context) {
        controller.viewportDidChange = viewportDidChange
        if controller.connection !== connection {
            controller.connection = connection
        }
        controller.update(source: source, configuration: configuration)
    }
}

#endif
