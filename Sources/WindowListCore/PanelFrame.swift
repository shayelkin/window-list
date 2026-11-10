import AppKit

/// Vertical sizing of the list panel: as tall as its content, but never taller than the usable screen.
public enum PanelFrame {
    /// `frame` resized to `height` (clamped to `visible`), keeping its top edge so it grows downwards; once the bottom
    /// reaches `visible.minY` it grows upwards instead. The result always lies vertically within `visible`.
    public static func fitting(_ frame: CGRect, height: CGFloat, in visible: CGRect) -> CGRect {
        let height = min(max(height, 0), visible.height)
        let top = min(frame.maxY, visible.maxY)
        let bottom = max(top - height, visible.minY)
        return CGRect(x: frame.minX, y: bottom, width: frame.width, height: height)
    }

    /// Resizes `panel` so the area below its titlebar is `contentHeight` tall, within its screen's visible frame
    /// (the screen minus the menu bar and a Dock that is not hidden). The user can then only resize its width.
    @MainActor
    public static func fit(_ panel: NSPanel, contentHeight: CGFloat) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let titlebar = panel.frame.height - panel.contentLayoutRect.height
        let target = fitting(panel.frame, height: contentHeight + titlebar, in: screen.visibleFrame)
        panel.minSize.height = target.height
        panel.maxSize.height = target.height
        panel.setFrame(target, display: true)
    }
}
