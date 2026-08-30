import CoreGraphics

/// Measured sizes, keyed by item identity.
///
/// Keying on identity rather than position means a size survives reordering,
/// insertion, and removal — only genuinely new items need measuring. Entries are
/// dropped wholesale when something invalidates every measurement at once, such as a
/// Dynamic Type change.
struct SizeCache {

    private var storage: [AnyHashable: CGSize] = [:]

    init() {}

    subscript(id: AnyHashable) -> CGSize? {
        get { storage[id] }
        set { storage[id] = newValue }
    }

    var count: Int { storage.count }

    /// Whether every one of `ids` has a measured size.
    func contains(all ids: some Sequence<AnyHashable>) -> Bool {
        ids.allSatisfy { storage[$0] != nil }
    }

    /// Drops measurements for items that are no longer in the data, so the cache can't
    /// grow without bound across long-lived canvases.
    mutating func retain(_ ids: Set<AnyHashable>) {
        guard storage.count > ids.count else { return }
        storage = storage.filter { ids.contains($0.key) }
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
    }
}
