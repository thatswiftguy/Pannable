import SwiftUI

extension View {
    /// `onChange(of:)` without the deprecation warning on newer systems.
    ///
    /// The two-parameter form arrived a major version after this package's floor, so
    /// both spellings are needed to stay warning-free across the supported range.
    @ViewBuilder
    func canvasOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17, macOS 14, watchOS 10, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}
