import SwiftUI

/// A handler an ancestor installs to watch a canvas's viewport.
///
/// The environment carries this downward, which is what lets a modifier written above
/// the canvas observe something the canvas only learns at scroll time. A preference
/// would flow the right direction but would push a view update through the whole
/// ancestor chain on every frame of a fling; a closure keeps the cost to whoever
/// actually asked for it.
struct CanvasViewportAction {
    var handler: (CanvasViewport) -> Void
}

private struct CanvasViewportActionKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: CanvasViewportAction? = nil
}

extension EnvironmentValues {
    var canvasViewportAction: CanvasViewportAction? {
        get { self[CanvasViewportActionKey.self] }
        set { self[CanvasViewportActionKey.self] = newValue }
    }
}

/// Composes viewport observers instead of replacing them.
///
/// Environment values normally overwrite, which would mean a canvas could report to
/// only one observer — a binding *or* a callback, never both. Chaining onto whatever is
/// already in scope lets several observers coexist, each seeing every change.
private struct CanvasViewportActionModifier: ViewModifier {

    @Environment(\.canvasViewportAction) private var existing

    var action: (CanvasViewport) -> Void

    func body(content: Content) -> some View {
        content.environment(
            \.canvasViewportAction,
            CanvasViewportAction { [existing, action] viewport in
                existing?.handler(viewport)
                action(viewport)
            }
        )
    }
}

extension View {

    /// Reports the canvas's viewport into a binding as it pans.
    ///
    /// ```swift
    /// @State private var viewport = CanvasViewport()
    ///
    /// PannableCanvas(nodes) { NodeCard(node: $0) }
    ///     .canvasViewport($viewport)
    /// ```
    ///
    /// The binding is written on every frame of a pan, so keep the views that depend on
    /// it small. Several observers can watch the same canvas; they compose rather than
    /// replacing one another.
    public func canvasViewport(_ viewport: Binding<CanvasViewport>) -> some View {
        modifier(CanvasViewportActionModifier { viewport.wrappedValue = $0 })
    }

    /// Calls `action` whenever the canvas's viewport changes.
    ///
    /// Composes with any other viewport observer already in scope.
    public func onCanvasViewportChange(_ action: @escaping (CanvasViewport) -> Void) -> some View {
        modifier(CanvasViewportActionModifier(action: action))
    }
}
