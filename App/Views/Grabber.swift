import SwiftUI

/// A visible handle at the top of the borderless panel, hinting that it can be dragged.
struct Grabber: View {
    static let height: CGFloat = 14

    var body: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
    }
}
