import AppKit

/// What a click on the menu bar icon does: a right click opens `StatusMenu`, any other click toggles the panel.
public enum StatusItemClick: Equatable, Sendable {
    case toggle
    case menu

    public init(_ type: NSEvent.EventType) {
        switch type {
        case .rightMouseDown, .rightMouseUp: self = .menu
        default: self = .toggle
        }
    }
}

/// The menu bar icon's right-click menu.
@MainActor
public enum StatusMenu {
    public static let showTitle = "Show"
    public static let hideTitle = "Hide"
    public static let quitTitle = "Quit WindowList"

    /// A menu whose first item sends `toggle` to `target`, titled for hiding the panel when `panelVisible` and for
    /// showing it otherwise, and whose last item quits the app.
    public static func make(panelVisible: Bool, toggle: Selector, target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        let toggleItem = menu.addItem(
            withTitle: panelVisible ? hideTitle : showTitle, action: toggle, keyEquivalent: "")
        toggleItem.target = target
        menu.addItem(.separator())
        let quitItem = menu.addItem(
            withTitle: quitTitle, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApplication.shared
        return menu
    }
}
