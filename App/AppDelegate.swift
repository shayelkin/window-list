import AppKit
import WindowListCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = WindowListModel()
    private var panel: FloatingPanel?
    private var contentHeight: CGFloat? {
        didSet { fitPanel() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = WindowListView(model: model) { [weak self] height in self?.contentHeight = height }
        let panel = FloatingPanel(content: view)
        panel.delegate = self
        panel.orderFrontRegardless()
        self.panel = panel
        fitPanel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    /// The panel is the only way to reach the app (no Dock icon, no menu bar), so closing it quits. Not
    /// `applicationShouldTerminateAfterLastWindowClosed`, which would also fire if the panel were ever ordered out.
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }

    func windowDidChangeScreen(_ notification: Notification) { fitPanel() }

    @objc private func screenParametersDidChange(_ notification: Notification) { fitPanel() }

    private func fitPanel() {
        guard let panel, let contentHeight else { return }
        PanelFrame.fit(panel, contentHeight: contentHeight)
    }
}
