#if os(watchOS)

import CoreGraphics
import SwiftUI

/// The canvas state for watchOS.
///
/// watchOS has neither `UIScrollView` nor `UIHostingController`, so there is nothing to
/// wrap and nothing to measure with. What it does have is the same layout engine and
/// the same spatial index, so the canvas still computes real frames and still builds
/// only the items the viewport can reach — the difference is that the viewport is moved
/// by a `DragGesture` and the Digital Crown rather than by a scroll view.
///
/// Because there is no way to measure a SwiftUI view off screen here, items take their
/// size from ``SwiftUI/View/canvasItemSize(_:)`` when it is set and from
/// ``SwiftUI/View/canvasEstimatedItemSize(_:)`` otherwise. Set one of them for a canvas
/// whose items are not all the same size.
@MainActor
final class WatchCanvasController<Content: View>: ObservableObject, CanvasHostControlling {

    /// The top-left of the viewport, in canvas coordinates.
    @Published var origin: CGPoint = .zero

    /// Bumped whenever the resolved frames change, so the view rebuilds.
    @Published private(set) var revision = 0

    @Published var isDragging = false

    private var engine: CanvasEngine<Content>?

    /// The size of the area the canvas is drawn into.
    private(set) var viewportSize: CGSize = .zero

    var viewportDidChange: (CanvasViewport) -> Void = { _ in }

    weak var connection: CanvasConnection? {
        didSet { connection?.host = self }
    }

    nonisolated init() {}

    // MARK: - Updating

    func update(source: CanvasItemSource<Content>, configuration: CanvasConfiguration) {
        guard let engine else {
            let engine = CanvasEngine(source: source, configuration: configuration)
            engine.resolve()
            self.engine = engine
            revision += 1
            return
        }

        if engine.update(source: source, configuration: configuration).needsLayout {
            engine.resolve()
            clampOrigin()
            revision += 1
        }
    }

    func viewportSizeChanged(to size: CGSize) {
        guard size != viewportSize else { return }
        let isFirstLayout = viewportSize == .zero
        viewportSize = size

        if isFirstLayout, let engine {
            // The starting position can only be computed once the viewport has a size.
            let anchor = engine.configuration.initialAnchor
            let travel = maximumOrigin
            origin = CGPoint(x: travel.x * anchor.x, y: travel.y * anchor.y)
        } else {
            clampOrigin()
        }
        publishViewport()
    }

    // MARK: - Reading the layout

    var contentSize: CGSize { engine?.contentSize ?? .zero }

    /// The items the viewport can currently reach.
    func visibleIndices() -> [Int] {
        guard let engine else { return [] }
        let overscan = engine.configuration.overscan
        return engine.visibleIndices(in: visibleRect.insetBy(dx: -overscan, dy: -overscan))
    }

    func frame(at position: Int) -> CGRect? { engine?.frame(at: position) }

    func content(at position: Int) -> Content? {
        guard let engine, position < engine.source.count else { return nil }
        return engine.content(at: position)
    }

    // MARK: - Panning

    var maximumOrigin: CGPoint {
        CGPoint(
            x: max(0, contentSize.width - viewportSize.width),
            y: max(0, contentSize.height - viewportSize.height)
        )
    }

    func setOrigin(_ point: CGPoint) {
        let travel = maximumOrigin
        origin = CGPoint(
            x: min(max(point.x, 0), travel.x),
            y: min(max(point.y, 0), travel.y)
        )
        publishViewport()
    }

    private func clampOrigin() {
        setOrigin(origin)
    }

    private var visibleRect: CGRect {
        CGRect(origin: origin, size: viewportSize)
    }

    func publishViewport() {
        let viewport = currentViewport
        viewportDidChange(viewport)
        connection?.viewport = viewport
    }

    // MARK: - CanvasHostControlling

    var currentViewport: CanvasViewport {
        CanvasViewport(
            visibleRect: visibleRect,
            contentSize: contentSize,
            isDragging: isDragging,
            isDecelerating: false
        )
    }

    func frame(forItemWith id: AnyHashable) -> CGRect? {
        engine?.frame(forItemWith: id)
    }

    func scrollTo(rect: CGRect, anchor: UnitPoint, animated: Bool) {
        let target = CGPoint(
            x: rect.minX + rect.width * anchor.x - viewportSize.width * anchor.x,
            y: rect.minY + rect.height * anchor.y - viewportSize.height * anchor.y
        )
        if animated {
            withAnimation(.easeOut(duration: 0.3)) { setOrigin(target) }
        } else {
            setOrigin(target)
        }
    }
}

#endif
