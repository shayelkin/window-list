import AppKit

/// Window configuration of the floating list panel, shared with the live tests that verify its Space behaviour.
@MainActor
public enum PanelStyle {
    public static let styleMask: NSWindow.StyleMask = [
        .titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView,
    ]
    public static let level: NSWindow.Level = .floating
    /// Every desktop Space, but no full-screen Space: for an accessory (LSUIElement) app `.canJoinAllSpaces` alone
    /// also shows the panel over full-screen apps, and `.fullScreenNone` keeps it off them.
    public static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenNone]

    public static func apply(to panel: NSPanel) {
        panel.styleMask = styleMask
        panel.level = level
        panel.collectionBehavior = collectionBehavior
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
    }
}
