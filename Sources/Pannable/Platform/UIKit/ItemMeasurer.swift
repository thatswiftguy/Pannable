#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

/// Measures item views without putting them on screen.
///
/// One hosting controller is reused for every measurement rather than one per item.
/// It is parented to the canvas's own view controller so it inherits the same trait
/// collection — without that, an item would measure at the default Dynamic Type size
/// and lay out at the user's.
@MainActor
final class ItemMeasurer<Content: View> {

    private let controller = UIHostingController<Content?>(rootView: nil)

    init(parent: UIViewController) {
        parent.addChild(controller)
        controller.view.frame = .zero
        controller.view.isHidden = true
        parent.view.addSubview(controller.view)
        controller.didMove(toParent: parent)

        if #available(iOS 16.4, tvOS 16.4, *) {
            controller.safeAreaRegions = []
        }
    }

    /// The size `content` wants, given the width the canvas can offer it.
    ///
    /// A `nil` width means the canvas is sizing itself to its content and has no width
    /// to offer, so the item is measured unconstrained.
    func measure(_ content: Content, proposedWidth: CGFloat?) -> CGSize {
        controller.rootView = content
        defer { controller.rootView = nil }

        let width = proposedWidth.map { $0 > 0 ? $0 : CGFloat.greatestFiniteMagnitude }
            ?? CGFloat.greatestFiniteMagnitude
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

#endif
