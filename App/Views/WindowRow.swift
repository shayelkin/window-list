import AppKit
import SwiftUI

/// A menu-item-style row: icon and title, with the accent-colored highlight menus use under the pointer.
struct WindowRow: View {
    let title: String
    let icon: NSImage?
    let isHighlighted: Bool
    let onHover: (Bool) -> Void
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "macwindow")
                }
            }
            .frame(width: 18, height: 18)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onActivate)
    }
}
