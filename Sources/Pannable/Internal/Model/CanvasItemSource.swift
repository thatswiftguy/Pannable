import SwiftUI

/// A canvas's data, flattened to what the hosts actually need: a stable identity per
/// item and a way to build its view.
///
/// Erasing the collection and ID types here keeps the platform hosts from having to be
/// generic over them. `Content` stays generic on purpose — routing it through `AnyView`
/// would cost a boxed allocation per item on every update.
struct CanvasItemSource<Content: View> {

    /// One identity per item, in order.
    var ids: [AnyHashable]

    /// Builds the view for the item at a position.
    var content: (Int) -> Content

    var count: Int { ids.count }

    var isEmpty: Bool { ids.isEmpty }

    init(ids: [AnyHashable], content: @escaping (Int) -> Content) {
        self.ids = ids
        self.content = content
    }

    init<Data: RandomAccessCollection, ID: Hashable>(
        data: Data,
        id: KeyPath<Data.Element, ID>,
        content builder: @escaping (Data.Element) -> Content
    ) {
        self.ids = data.map { AnyHashable($0[keyPath: id]) }
        self.content = { position in
            // O(1) for a RandomAccessCollection.
            builder(data[data.index(data.startIndex, offsetBy: position)])
        }
    }

    /// The item at a position, or `nil` if the position is out of range.
    func id(at position: Int) -> AnyHashable? {
        ids.indices.contains(position) ? ids[position] : nil
    }

    /// The position of the item with this identity, or `nil` if it isn't present.
    func position(of id: AnyHashable) -> Int? {
        ids.firstIndex(of: id)
    }
}
