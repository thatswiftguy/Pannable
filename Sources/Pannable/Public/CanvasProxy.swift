import CoreGraphics
import SwiftUI

/// A handle for moving a canvas's viewport programmatically.
///
/// Obtain one from ``CanvasReader``, the same way `ScrollViewProxy` comes from
/// `ScrollViewReader`.
///
/// ```swift
/// CanvasReader { proxy in
///     PannableCanvas(nodes) { NodeCard(node: $0) }
///         .toolbar {
///             Button("Reveal selection") { proxy.scrollTo(selection) }
///         }
/// }
/// ```
@MainActor
public struct CanvasProxy {

    private let connection: CanvasConnection

    init(connection: CanvasConnection) {
        self.connection = connection
    }

    /// What the canvas is currently showing.
    public var viewport: CanvasViewport {
        connection.host?.currentViewport ?? connection.viewport
    }

    /// Moves the viewport so the item with this identity sits at `anchor`.
    ///
    /// Does nothing if no item has that identity.
    ///
    /// - Parameters:
    ///   - id: The identity of the item to reveal — the same value the canvas's data
    ///     provides through `Identifiable` or through its `id` key path.
    ///   - anchor: Where in the viewport the item should land. `.center` centers it,
    ///     `.topLeading` brings it to the upper-left corner.
    ///   - animated: Whether to animate the move. Defaults to `true`.
    public func scrollTo(_ id: some Hashable, anchor: UnitPoint = .center, animated: Bool = true) {
        guard let host = connection.host, let frame = host.frame(forItemWith: AnyHashable(id)) else { return }
        host.scrollTo(rect: frame, anchor: anchor, animated: animated)
    }

    /// Moves the viewport so this canvas-space point sits at `anchor`.
    public func scrollTo(_ point: CGPoint, anchor: UnitPoint = .center, animated: Bool = true) {
        scrollTo(CGRect(origin: point, size: .zero), anchor: anchor, animated: animated)
    }

    /// Moves the viewport so this canvas-space rectangle sits at `anchor`.
    public func scrollTo(_ rect: CGRect, anchor: UnitPoint = .center, animated: Bool = true) {
        connection.host?.scrollTo(rect: rect, anchor: anchor, animated: animated)
    }
}

/// A view that gives its content a ``CanvasProxy`` for the canvas inside it.
///
/// Mirrors `ScrollViewReader`: wrap a canvas, and everything in the closure can move
/// its viewport.
///
/// ```swift
/// CanvasReader { proxy in
///     VStack {
///         Button("Go to origin") { proxy.scrollTo(.zero, anchor: .topLeading) }
///         PannableCanvas(nodes) { NodeCard(node: $0) }
///     }
/// }
/// ```
@MainActor
public struct CanvasReader<Content: View>: View {

    @StateObject private var connection = CanvasConnection()

    private let content: (CanvasProxy) -> Content

    public init(@ViewBuilder content: @escaping (CanvasProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(CanvasProxy(connection: connection))
            .environment(\.canvasConnection, connection)
    }
}
