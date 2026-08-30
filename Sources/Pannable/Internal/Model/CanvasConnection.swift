import CoreGraphics
import SwiftUI

/// What a ``CanvasProxy`` needs from whichever platform host is on screen.
///
/// The three hosts are wildly different underneath — `UIScrollView`, `NSScrollView`,
/// and a SwiftUI offset — but they all answer these, so the proxy is written once.
@MainActor
protocol CanvasHostControlling: AnyObject {
    func scrollTo(rect: CGRect, anchor: UnitPoint, animated: Bool)
    func frame(forItemWith id: AnyHashable) -> CGRect?
    var currentViewport: CanvasViewport { get }
}

/// The link between a ``CanvasReader`` and the canvas beneath it.
///
/// The reader creates one and puts it in the environment; the canvas finds it there and
/// registers itself. That indirection is what lets `content` reference a proxy for a
/// canvas that doesn't exist yet when the closure runs.
@MainActor
final class CanvasConnection: ObservableObject {

    /// Weak, because the host owns its view tree and this must not keep it alive past
    /// its time on screen.
    weak var host: (any CanvasHostControlling)?

    @Published var viewport = CanvasViewport()

    nonisolated init() {}
}

private struct CanvasConnectionKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: CanvasConnection? = nil
}

extension EnvironmentValues {
    var canvasConnection: CanvasConnection? {
        get { self[CanvasConnectionKey.self] }
        set { self[CanvasConnectionKey.self] = newValue }
    }
}
