/// The items of a listed window's right-click menu, in display order.
public enum WindowMenuAction: CaseIterable, Sendable {
    case switchTo
    case close

    public var title: String {
        switch self {
        case .switchTo: "Switch To"
        case .close: "Close"
        }
    }
}
