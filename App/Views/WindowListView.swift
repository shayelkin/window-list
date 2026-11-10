import SwiftUI
import WindowListCore

struct WindowListView: View {
    let model: WindowListModel
    /// Reports the height the content needs below the titlebar.
    let onContentHeight: (CGFloat) -> Void

    var body: some View {
        if model.isTrusted {
            list
        } else {
            PermissionView(request: model.requestPermission, onContentHeight: onContentHeight)
        }
    }

    private var list: some View {
        ScrollView {
            if model.entries.isEmpty {
                Text("No windows")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        WindowRow(
                            title: entry.title,
                            icon: model.icon(for: entry.process),
                            isHighlighted: model.highlight.id == entry.id,
                            onHover: { inside in hover(entry.id, inside: inside) },
                            onActivate: { model.activate(entry.id) }
                        )
                    }
                }
                .padding(5)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in onContentHeight(height) }
    }

    private func hover(_ id: WindowID, inside: Bool) {
        if inside {
            model.highlight(id)
            return
        }
        guard model.highlight.id == id else { return }
        model.highlight(nil)
    }
}
