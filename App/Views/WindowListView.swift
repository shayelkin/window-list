import SwiftUI
import WindowListCore

struct WindowListView: View {
    let model: WindowListModel

    var body: some View {
        if model.isTrusted {
            list
        } else {
            PermissionView(request: model.requestPermission)
        }
    }

    private var list: some View {
        ScrollView {
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
        .overlay {
            if model.entries.isEmpty {
                Text("No windows").foregroundStyle(.secondary)
            }
        }
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
