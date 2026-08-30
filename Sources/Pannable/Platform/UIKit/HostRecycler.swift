#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

/// A pool of hosting controllers shared by whichever items are currently visible.
///
/// Hosting a view controller is not cheap, and a canvas crossing a large data set would
/// otherwise create and destroy them continuously while panning. Pooled controllers are
/// kept as children of the canvas's view controller for their whole lifetime — only
/// their views enter and leave the content view, and only their root view changes — so
/// reuse costs a property assignment rather than view-controller containment.
@MainActor
final class HostRecycler<Content: View> {

    private unowned let parent: UIViewController
    private unowned let container: UIView

    private var active: [Int: UIHostingController<Content?>] = [:]
    private var pool: [UIHostingController<Content?>] = []

    init(parent: UIViewController, container: UIView) {
        self.parent = parent
        self.container = container
    }

    /// How many controllers are currently on screen. Used by tests to prove that
    /// virtualization is doing its job.
    var activeCount: Int { active.count }

    /// Total controllers held, on screen or pooled.
    var allocatedCount: Int { active.count + pool.count }

    var activePositions: Set<Int> { Set(active.keys) }

    /// Brings exactly `positions` on screen, reusing controllers for everything else.
    func setVisible(
        _ positions: [Int],
        content: (Int) -> Content,
        frame: (Int) -> CGRect?
    ) {
        let wanted = Set(positions)

        for position in active.keys where !wanted.contains(position) {
            recycle(position)
        }

        for position in positions {
            guard let frame = frame(position) else { continue }
            if let host = active[position] {
                if host.view.frame != frame { host.view.frame = frame }
            } else {
                let host = dequeue()
                host.rootView = content(position)
                host.view.frame = frame
                container.addSubview(host.view)
                active[position] = host
            }
        }
    }

    /// Rebuilds the root view of everything on screen.
    ///
    /// Item identities can survive a data change while their contents do not, so the
    /// visible views are refreshed on every update pass. SwiftUI diffs the new root
    /// view against the old, making this cheap when nothing actually changed.
    func refreshContent(_ content: (Int) -> Content) {
        for (position, host) in active {
            host.rootView = content(position)
        }
    }

    /// Returns everything to the pool, for when the layout changed wholesale.
    func recycleAll() {
        for position in active.keys {
            recycle(position)
        }
    }

    private func recycle(_ position: Int) {
        guard let host = active.removeValue(forKey: position) else { return }
        host.view.removeFromSuperview()
        // Dropping the root view releases whatever the item's view was holding.
        host.rootView = nil
        pool.append(host)
    }

    private func dequeue() -> UIHostingController<Content?> {
        if let reused = pool.popLast() { return reused }

        let host = UIHostingController<Content?>(rootView: nil)
        // Items must not paint an opaque backdrop over the canvas style behind them.
        host.view.backgroundColor = .clear
        if #available(iOS 16.4, tvOS 16.4, *) {
            host.safeAreaRegions = []
        }
        parent.addChild(host)
        host.didMove(toParent: parent)
        return host
    }
}

#endif
