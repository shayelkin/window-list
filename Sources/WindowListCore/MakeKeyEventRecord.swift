import CoreGraphics

/// The synthetic `CGSEventRecord` posted via `SLPSPostEventRecordTo` to make another app's window key.
/// Offsets and values adapted from AltTab (which credits yabai/Hammerspoon and CGSInternal's CGSEvent.h):
/// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/SkyLight.framework.swift
public struct MakeKeyEventRecord: Sendable {
    public static let byteCount = 0x100
    public static let lengthOffset = 0x04
    public static let recordLength: UInt8 = 0xf8
    public static let eventTypeOffset = 0x08
    public static let leftMouseDown: UInt8 = 0x01
    public static let windowLocationOffset = 0x20
    public static let flagOffset = 0x3a
    public static let flagValue: UInt8 = 0x10
    public static let windowIDOffset = 0x3c
    /// Far past any window's bottom-right corner, so no control is ever hit (see AltTab's notes on #5381/#5900).
    public static let offWindowPoint = CGPoint(x: 300_000, y: 300_000)

    public private(set) var bytes: InlineArray<256, UInt8>

    public init(window: WindowID) {
        var bytes = InlineArray<256, UInt8>(repeating: 0)
        bytes[Self.lengthOffset] = Self.recordLength
        bytes[Self.eventTypeOffset] = Self.leftMouseDown
        bytes.storeLittleEndian(Double(Self.offWindowPoint.x).bitPattern, at: Self.windowLocationOffset)
        bytes.storeLittleEndian(Double(Self.offWindowPoint.y).bitPattern, at: Self.windowLocationOffset + 8)
        bytes[Self.flagOffset] = Self.flagValue
        bytes.storeLittleEndian(window.rawValue, at: Self.windowIDOffset)
        self.bytes = bytes
    }

    public var windowLocation: CGPoint {
        CGPoint(
            x: Double(bitPattern: bytes.loadLittleEndian(UInt64.self, at: Self.windowLocationOffset)),
            y: Double(bitPattern: bytes.loadLittleEndian(UInt64.self, at: Self.windowLocationOffset + 8))
        )
    }
}
