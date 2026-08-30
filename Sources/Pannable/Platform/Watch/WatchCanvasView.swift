#if os(watchOS)

import CoreGraphics
import SwiftUI

/// The watchOS canvas.
///
/// Only the items intersecting the viewport are placed, exactly as on the other
/// platforms — the culling comes from the same spatial index. Panning is a drag
/// gesture, with the Digital Crown driving the vertical axis for precise movement.
struct WatchCanvasView<Content: View>: View {

    var source: CanvasItemSource<Content>
    var configuration: CanvasConfiguration
    var connection: CanvasConnection?
    var viewportDidChange: (CanvasViewport) -> Void

    @StateObject private var controller = WatchCanvasController<Content>()

    /// The viewport origin when the current drag began, so translation is applied to a
    /// fixed base rather than compounding every frame.
    @State private var dragAnchor: CGPoint?

    @State private var crownPosition: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // A transparent backdrop gives the drag gesture something to land on
                // even where the canvas has no items.
                Color.clear
                    .contentShape(Rectangle())

                ForEach(controller.visibleIndices(), id: \.self) { position in
                    if let frame = controller.frame(at: position), let content = controller.content(at: position) {
                        content
                            .frame(width: frame.width, height: frame.height)
                            .offset(
                                x: frame.minX - controller.origin.x,
                                y: frame.minY - controller.origin.y
                            )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .gesture(panGesture)
            .focusable()
            .digitalCrownRotation(
                $crownPosition,
                from: 0,
                through: max(controller.maximumOrigin.y, 1),
                by: 8,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onAppear {
                controller.viewportDidChange = viewportDidChange
                // Claimed on appearance: SwiftUI can build more than one host for a
                // given canvas, and only the visible one has a viewport worth reporting.
                controller.connection = connection
                controller.claimConnection()
                controller.update(source: source, configuration: configuration)
                controller.viewportSizeChanged(to: geometry.size)
                crownPosition = controller.origin.y
            }
            .onDisappear { controller.releaseConnection() }
            .canvasOnChange(of: geometry.size) { controller.viewportSizeChanged(to: $0) }
            .canvasOnChange(of: crownPosition) { position in
                // Ignore the echo from a drag that just moved the crown's own binding.
                guard dragAnchor == nil else { return }
                controller.setOrigin(CGPoint(x: controller.origin.x, y: position))
            }
        }
        .onChangeOfCanvasInputs(source: source, configuration: configuration) {
            controller.viewportDidChange = viewportDidChange
            controller.connection = connection
            controller.update(source: source, configuration: configuration)
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = dragAnchor ?? controller.origin
                if dragAnchor == nil {
                    dragAnchor = base
                    controller.isDragging = true
                }
                controller.setOrigin(
                    CGPoint(
                        x: base.x - value.translation.width,
                        y: base.y - value.translation.height
                    )
                )
            }
            .onEnded { _ in
                dragAnchor = nil
                controller.isDragging = false
                // Keep the crown in step with where the drag left the viewport.
                crownPosition = controller.origin.y
                controller.publishViewport()
            }
    }
}

private extension View {
    /// Re-applies the canvas inputs whenever SwiftUI hands down new ones.
    func onChangeOfCanvasInputs<Content: View>(
        source: CanvasItemSource<Content>,
        configuration: CanvasConfiguration,
        perform action: @escaping () -> Void
    ) -> some View {
        // The content closure captures fresh data on every pass, so it is re-applied
        // unconditionally; identity and configuration decide whether that costs a
        // re-layout.
        canvasOnChange(of: CanvasInputToken(ids: source.ids, configuration: configuration)) { _ in
            action()
        }
    }
}

/// The part of a canvas's inputs that can invalidate its layout.
private struct CanvasInputToken: Equatable {
    var ids: [AnyHashable]
    var configuration: CanvasConfiguration
}

#endif
