#if canImport(UIKit) && !os(watchOS)

import UIKit

/// The canvas's scroll view, with VoiceOver traversal made to work in two dimensions.
///
/// Virtualization means items outside the viewport are not in the view hierarchy at all,
/// so VoiceOver cannot reach them by swiping — the same situation a table view is in,
/// and it is solved the same way, by letting the three-finger scroll gesture page the
/// content. The default implementation only handles the vertical axis; a canvas needs
/// all four directions to be traversable.
final class CanvasScrollView: UIScrollView {

    /// How much of the previous screen stays visible after a paging scroll, so a user
    /// keeps their bearings rather than jumping to wholly unfamiliar content.
    private static let pageOverlap: CGFloat = 0.15

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let page = CGSize(
            width: bounds.width * (1 - Self.pageOverlap),
            height: bounds.height * (1 - Self.pageOverlap)
        )

        var target = contentOffset
        switch direction {
        case .left, .next: target.x += page.width
        case .right, .previous: target.x -= page.width
        case .up: target.y -= page.height
        case .down: target.y += page.height
        @unknown default: return false
        }

        let limit = CGPoint(
            x: max(0, contentSize.width - bounds.width),
            y: max(0, contentSize.height - bounds.height)
        )
        let clamped = CGPoint(
            x: min(max(target.x, 0), limit.x),
            y: min(max(target.y, 0), limit.y)
        )

        // Reporting failure at the edge is what tells VoiceOver to announce the boundary
        // rather than silently doing nothing.
        guard clamped != contentOffset else { return false }

        setContentOffset(clamped, animated: false)
        UIAccessibility.post(notification: .pageScrolled, argument: nil)
        return true
    }
}

#endif
