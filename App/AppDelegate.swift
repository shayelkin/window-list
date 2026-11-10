import AppKit
import OSLog
import SwiftUI
import WindowListCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = WindowListModel()
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?
    private var contentHeight: CGFloat? {
        didSet { fitPanel() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = VStack(spacing: 0) {
            Grabber()
            WindowListView(model: model) { [weak self] height in self?.contentHeight = Grabber.height + height }
        }
        .gesture(WindowDragGesture())
        let panel = FloatingPanel(content: view)
        panel.delegate = self
        panel.orderFrontRegardless()
        self.panel = panel
        statusItem = makeStatusItem()
        do {
            hotKey = try GlobalHotKey(.toggleList) { [weak self] in self?.togglePanel(nil) }
        } catch {
            Logger().error("Could not register keyboard shortcut: \(String(describing: error), privacy: .public)")
        }
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

    func windowDidChangeScreen(_ notification: Notification) { fitPanel() }

    @objc private func screenParametersDidChange(_ notification: Notification) { fitPanel() }

    @objc private func statusItemClicked(_ sender: Any?) {
        switch StatusItemClick(NSApp.currentEvent?.type ?? .leftMouseUp) {
        case .toggle: togglePanel(sender)
        case .menu: showMenu()
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard let panel else { return }
        PanelVisibility.toggle(panel)
    }

    /// Attached only while it is open, so a left click keeps toggling the panel instead of opening the menu.
    private func showMenu() {
        guard let panel, let statusItem else { return }
        statusItem.menu = StatusMenu.make(panelVisible: panel.isVisible, toggle: #selector(togglePanel), target: self)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Window List")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    private func fitPanel() {
        guard let panel, let contentHeight else { return }
        PanelFrame.fit(panel, contentHeight: contentHeight)
    }
}
