public protocol WindowOrderable {
    var id: WindowID { get }
    var appName: String { get }
    var title: String { get }
}

/// How a listed window can be reached through Accessibility.
public enum WindowAccess: Sendable {
    /// The window's AX element is known.
    case resolved(AXWindow)
    /// A window on a hidden Space whose AX element no client has requested yet, so it cannot be found by id; it
    /// is reachable only by focusing it through WindowServer first.
    case unresolved
}

public struct WindowEntry: Identifiable, Sendable, Equatable, WindowOrderable {
    public let id: WindowID
    public let process: ProcessID
    public let appName: String
    public let title: String
    public let isMinimized: Bool
    public let access: WindowAccess

    public init(window: AXWindow, process: ProcessID, appName: String, title: String, isMinimized: Bool) {
        self.id = window.id
        self.process = process
        self.appName = appName
        self.title = title.isEmpty ? appName : title
        self.isMinimized = isMinimized
        self.access = .resolved(window)
    }

    /// An unseen window: no title is available without Screen Recording permission, so the app name stands in.
    public init(unresolved id: WindowID, process: ProcessID, appName: String) {
        self.id = id
        self.process = process
        self.appName = appName
        self.title = appName
        self.isMinimized = false
        self.access = .unresolved
    }

    public var isResolved: Bool {
        switch access {
        case .resolved: true
        case .unresolved: false
        }
    }

    public static func == (lhs: WindowEntry, rhs: WindowEntry) -> Bool {
        lhs.id == rhs.id && lhs.process == rhs.process && lhs.appName == rhs.appName && lhs.title == rhs.title
            && lhs.isMinimized == rhs.isMinimized && lhs.isResolved == rhs.isResolved
    }
}
