import SwiftUI

struct PermissionView: View {
    let request: () -> Void
    let onContentHeight: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary)
            Text("Accessibility access needed").font(.headline)
            Text("WindowList uses Accessibility to list and focus windows on every desktop.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Accessibility Settings", action: request)
        }
        .padding()
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height, action: onContentHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
