import CoreGraphics
import Darwin

public struct ProcessID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: pid_t

    public init?(_ rawValue: pid_t) {
        guard rawValue > 0 else { return nil }
        self.rawValue = rawValue
    }

    public static let current: ProcessID = {
        let pid = getpid()
        guard let id = ProcessID(pid) else { preconditionFailure("getpid() returned non-positive \(pid)") }
        return id
    }()

    public var description: String { "pid \(rawValue)" }
}

public struct WindowID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: CGWindowID

    public init?(_ rawValue: CGWindowID) {
        guard rawValue != 0 else { return nil }
        self.rawValue = rawValue
    }

    public static func < (lhs: WindowID, rhs: WindowID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "wid \(rawValue)" }
}

public struct AXElementID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) { self.rawValue = rawValue }

    public static let zero = AXElementID(0)

    public var successor: AXElementID? {
        let (next, overflow) = rawValue.addingReportingOverflow(1)
        return overflow ? nil : AXElementID(next)
    }

    public static func < (lhs: AXElementID, rhs: AXElementID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "axid \(rawValue)" }
}
