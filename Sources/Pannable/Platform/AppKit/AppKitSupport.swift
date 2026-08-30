#if os(macOS)

import AppKit
import SwiftUI

/// A document view that uses top-left origin coordinates.
///
/// AppKit measures from the bottom-left by default. Flipping it means canvas
/// coordinates mean the same thing on every platform, so the shared layout engine's
/// output can be used verbatim rather than being mirrored on macOS alone.
final class FlippedCanvasContentView: NSView {

    override var isFlipped: Bool { true }

    /// The repeating backdrop drawn behind the items.
    var background: CanvasBackground = .none {
        didSet {
            guard background != oldValue else { return }
            refreshPattern()
        }
    }

    private var patternColor: NSColor?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The backdrop is a rendered bitmap, so it must be redrawn for the new
        // appearance; a dynamic colour cannot adapt once baked into a pattern.
        refreshPattern()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let patternColor, let context = NSGraphicsContext.current else { return }
        // Anchor the tiling to this view's own origin rather than the window's, so the
        // pattern stays fixed to canvas coordinates as the canvas is panned.
        context.patternPhase = convert(NSPoint.zero, to: nil)
        patternColor.setFill()
        dirtyRect.fill()
    }

    private func refreshPattern() {
        patternColor = background.patternColor(for: effectiveAppearance)
        needsDisplay = true
    }
}

/// Measures item views without putting them on screen.
///
/// One hosting controller is reused for every measurement rather than one per item, and
/// it is parented to the canvas's own controller so it inherits the same environment.
@MainActor
final class AppKitItemMeasurer<Content: View> {

    private let controller = NSHostingController<Content?>(rootView: nil)

    init(parent: NSViewController) {
        parent.addChild(controller)
        controller.view.frame = .zero
        controller.view.isHidden = true
        parent.view.addSubview(controller.view)
    }

    /// The size `content` wants, given the width the canvas can offer it.
    func measure(_ content: Content, proposedWidth: CGFloat?) -> CGSize {
        controller.rootView = content
        defer { controller.rootView = nil }

        let width = proposedWidth.map { $0 > 0 ? $0 : CGFloat.greatestFiniteMagnitude }
            ?? CGFloat.greatestFiniteMagnitude
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

/// A pool of hosting controllers shared by whichever items are currently visible.
///
/// Pooled controllers stay children of the canvas's controller for their whole
/// lifetime; only their views enter and leave the content view, so reuse costs a
/// property assignment rather than view-controller containment.
@MainActor
final class AppKitHostRecycler<Content: View> {

    private unowned let parent: NSViewController
    private unowned let container: NSView

    private var active: [Int: NSHostingController<Content?>] = [:]
    private var pool: [NSHostingController<Content?>] = []

    init(parent: NSViewController, container: NSView) {
        self.parent = parent
        self.container = container
    }

    var activeCount: Int { active.count }
    var allocatedCount: Int { active.count + pool.count }

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

        // Subviews accumulate in recycle order, which is arbitrary. Stating the
        // accessibility order explicitly keeps VoiceOver reading items in the order the
        // data declares them.
        container.setAccessibilityChildren(positions.compactMap { active[$0]?.view })
    }

    func refreshContent(_ content: (Int) -> Content) {
        for (position, host) in active {
            host.rootView = content(position)
        }
    }

    func recycleAll() {
        for position in active.keys {
            recycle(position)
        }
    }

    private func recycle(_ position: Int) {
        guard let host = active.removeValue(forKey: position) else { return }
        host.view.removeFromSuperview()
        host.rootView = nil
        pool.append(host)
    }

    private func dequeue() -> NSHostingController<Content?> {
        if let reused = pool.popLast() { return reused }

        let host = NSHostingController<Content?>(rootView: nil)
        parent.addChild(host)
        return host
    }
}

#endif
