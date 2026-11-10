import AppKit
import SwiftUI
import WindowListCore

/// A non-activating utility panel that floats on every Space (but not over full-screen apps) and stays visible
/// while the app is inactive.
final class FloatingPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: PanelStyle.styleMask,
            backing: .buffered,
            defer: false
        )
        title = "Windows"
        PanelStyle.apply(to: self)
        becomesKeyOnlyIfNeeded = true
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 200, height: 160)

        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        let hosting = NSHostingView(rootView: content)
        // The panel's height follows the content through `PanelFrame.fit`; SwiftUI's default min/ideal/max size
        // constraints would otherwise force it, e.g. to the wrapped permission text's height at zero width.
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
        if !setFrameUsingName(Self.autosaveName) { center() }
        setFrameAutosaveName(Self.autosaveName)
    }

    private static let autosaveName = "WindowListPanel"

    /// Allows key focus (for future keyboard navigation) without activating the app, thanks to `.nonactivatingPanel`.
    override var canBecomeKey: Bool { true }
}
