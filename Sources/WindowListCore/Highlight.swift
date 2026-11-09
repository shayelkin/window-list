public struct Highlight: Equatable, Sendable {
    public private(set) var id: WindowID?

    public init(_ id: WindowID? = nil) { self.id = id }

    public mutating func set(_ id: WindowID?) { self.id = id }

    /// Clears the highlight when its window is no longer listed.
    public mutating func reconcile(with present: some Sequence<WindowID>) {
        guard let id, !present.contains(id) else { return }
        self.id = nil
    }
}
