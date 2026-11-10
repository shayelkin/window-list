import AppKit

/// Showing and hiding the list panel from the menu bar icon.
@MainActor
public enum PanelVisibility {
    /// Hides `panel` if it is visible, otherwise shows it without activating the app.
    public static func toggle(_ panel: NSWindow) {
        guard panel.isVisible else {
            panel.orderFrontRegardless()
            return
        }
        panel.orderOut(nil)
    }
}
