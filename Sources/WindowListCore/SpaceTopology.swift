import CoreGraphics
import Foundation

public struct SpaceID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init?(_ rawValue: UInt64) {
        guard rawValue != 0 else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { "space \(rawValue)" }
}

public struct DisplaySpaces: Equatable, Sendable, CustomStringConvertible {
    public let display: String
    public let current: SpaceID
    /// Regular desktop Spaces in Mission Control order (full-screen Spaces excluded).
    public let userSpaces: [SpaceID]

    public init(display: String, current: SpaceID, userSpaces: [SpaceID]) {
        self.display = display
        self.current = current
        self.userSpaces = userSpaces
    }

    public var description: String { "display \(display): current \(current), user spaces \(userSpaces)" }
}

public enum SpaceTopology {
    /// `type` of a regular desktop in `CGSCopyManagedDisplaySpaces` (full-screen Spaces are 4).
    public static let userSpaceType = 0

    /// Parses `CGSCopyManagedDisplaySpaces` output; malformed displays are dropped, malformed Spaces skipped.
    public static func parse(_ displays: [[String: Any]]) -> [DisplaySpaces] {
        displays.compactMap { dictionary in
            guard let display = dictionary["Display Identifier"] as? String,
                let currentInfo = dictionary["Current Space"] as? [String: Any],
                let current = spaceID(currentInfo["ManagedSpaceID"]),
                let spaces = dictionary["Spaces"] as? [[String: Any]]
            else { return nil }
            let userSpaces = spaces.compactMap { space -> SpaceID? in
                guard space["type"] as? Int == userSpaceType else { return nil }
                return spaceID(space["ManagedSpaceID"])
            }
            return DisplaySpaces(display: display, current: current, userSpaces: userSpaces)
        }
    }

    public static func displays() -> [DisplaySpaces] {
        guard let raw = PrivateAPI.managedDisplaySpaces() as? [[String: Any]] else { return [] }
        return parse(raw)
    }

    /// The Space currently shown on each display.
    public static func currentSpaces() -> Set<SpaceID> { Set(displays().map(\.current)) }

    public static func spaces(of window: WindowID) -> Set<SpaceID> {
        Set(PrivateAPI.spaces(of: window).compactMap(SpaceID.init))
    }

    /// Windows ordered in on any of `spaces`, shown or not. Windows an app keeps ordered out (hidden helpers, closed
    /// windows kept for reuse) still report a Space but are absent here.
    public static func orderedInWindows(on spaces: Set<SpaceID>) -> Set<WindowID> {
        Set(PrivateAPI.orderedInWindows(on: spaces.map(\.rawValue)).compactMap(WindowID.init))
    }

    /// An unseen window (no AX element yet) is listed only when it is ordered in, on some Space, and none of its
    /// Spaces is currently shown: on a shown Space, `kAXWindows` is authoritative, so a window it omits is not a real
    /// window.
    public static func shouldListUnresolved(
        windowSpaces: Set<SpaceID>, currentSpaces: Set<SpaceID>, isOrderedIn: Bool
    ) -> Bool {
        isOrderedIn && !windowSpaces.isEmpty && windowSpaces.isDisjoint(with: currentSpaces)
    }

    private static func spaceID(_ value: Any?) -> SpaceID? {
        guard let raw = value as? Int, let unsigned = UInt64(exactly: raw) else { return nil }
        return SpaceID(unsigned)
    }
}
