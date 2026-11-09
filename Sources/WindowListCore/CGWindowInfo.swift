import CoreGraphics

public struct WindowBounds: Hashable, Sendable {
    public static let minimumSide: CGFloat = 50

    public let rect: CGRect

    public init?(_ rect: CGRect) {
        let components = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        guard components.allSatisfy(\.isFinite),
            rect.size.width >= Self.minimumSide,
            rect.size.height >= Self.minimumSide
        else { return nil }
        self.rect = rect
    }
}

/// One entry of `CGWindowListCopyWindowInfo`, reduced to what is reliable without Screen Recording permission.
public struct CGWindowInfo: Hashable, Sendable {
    public let id: WindowID
    public let process: ProcessID
    public let bounds: WindowBounds

    public init?(dictionary: [String: Any], excluding own: ProcessID) {
        guard let number = dictionary[kCGWindowNumber as String] as? Int,
            let rawID = CGWindowID(exactly: number),
            let id = WindowID(rawID),
            let pidNumber = dictionary[kCGWindowOwnerPID as String] as? Int,
            let rawPID = pid_t(exactly: pidNumber),
            let process = ProcessID(rawPID),
            process != own,
            let layer = dictionary[kCGWindowLayer as String] as? Int,
            layer == 0,
            let alpha = dictionary[kCGWindowAlpha as String] as? Double,
            alpha.isFinite,
            alpha > 0,
            let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
            let rect = Self.rect(from: boundsDictionary),
            let bounds = WindowBounds(rect)
        else { return nil }
        self.id = id
        self.process = process
        self.bounds = bounds
    }

    /// `CGRect(dictionaryRepresentation:)` raises an Objective-C exception on non-numeric values, so parse explicitly.
    private static func rect(from dictionary: [String: Any]) -> CGRect? {
        guard let x = dictionary["X"] as? Double,
            let y = dictionary["Y"] as? Double,
            let width = dictionary["Width"] as? Double,
            let height = dictionary["Height"] as? Double
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// All on-screen and off-screen (other Space, minimized) windows.
    public static func inventory(excluding own: ProcessID = .current) -> [CGWindowInfo] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { CGWindowInfo(dictionary: $0, excluding: own) }
    }
}
