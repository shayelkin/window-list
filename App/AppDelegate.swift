import AppKit
import WindowListCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = WindowListModel()
    private var panel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = FloatingPanel(content: WindowListView(model: model))
        panel.delegate = self
        panel.orderFrontRegardless()
        self.panel = panel
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    /// The panel is the only way to reach the app (no Dock icon, no menu bar), so closing it quits. Not
    /// `applicationShouldTerminateAfterLastWindowClosed`, which would also fire if the panel were ever ordered out.
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
