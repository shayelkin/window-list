import AppKit

/// Window configuration of the floating list panel, shared with the live tests that verify its Space behaviour.
@MainActor
public enum PanelStyle {
    /// No title bar: the panel is moved by dragging its content and shown, hidden and quit from the menu bar icon.
    public static let styleMask: NSWindow.StyleMask = [.borderless, .resizable, .nonactivatingPanel]
    public static let level: NSWindow.Level = .floating
    /// Every desktop Space, but no full-screen Space: for an accessory (LSUIElement) app `.canJoinAllSpaces` alone
    /// also shows the panel over full-screen apps, and `.fullScreenNone` keeps it off them.
    public static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
    public static let cornerRadius: CGFloat = 12

    public static func apply(to panel: NSPanel) {
        panel.styleMask = styleMask
        panel.level = level
        panel.collectionBehavior = collectionBehavior
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // A borderless window has no frame to draw its rounded corners and shadow; the content's `cornerMask` shapes
        // it, so the window itself must be transparent around that shape.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
    }

    /// A stretchable rounded-rectangle mask with `cornerRadius` corners, for `NSVisualEffectView.maskImage`.
    public static func cornerMask() -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
