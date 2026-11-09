import CoreFoundation

/// The 20-byte token accepted by `_AXUIElementCreateWithRemoteToken`.
/// Layout adapted from AltTab:
/// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/ApplicationServices.HIServices.framework.swift
/// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/AXUIElement.swift
public struct RemoteToken: Sendable {
    public static let byteCount = 20
    public static let pidOffset = 0
    public static let paddingOffset = 4
    public static let magicOffset = 8
    public static let elementOffset = 12
    public static let magic: UInt32 = 0x636f_636f

    public private(set) var bytes: InlineArray<20, UInt8>

    public init(process: ProcessID, element: AXElementID) {
        var bytes = InlineArray<20, UInt8>(repeating: 0)
        bytes.storeLittleEndian(process.rawValue, at: Self.pidOffset)
        bytes.storeLittleEndian(Self.magic, at: Self.magicOffset)
        bytes.storeLittleEndian(element.rawValue, at: Self.elementOffset)
        self.bytes = bytes
    }
}

/// One reusable CFData for a brute-force sweep, so each candidate costs no allocation.
/// Reusing the buffer is safe because the created element parses the bytes rather than retaining them (measured by AltTab:
/// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/AXUIElement.swift).
final class RemoteTokenBuffer {
    private let data: CFMutableData

    init?() {
        guard let data = CFDataCreateMutable(kCFAllocatorDefault, RemoteToken.byteCount) else { return nil }
        CFDataSetLength(data, RemoteToken.byteCount)
        self.data = data
    }

    func load(_ token: RemoteToken) -> CFData? {
        guard CFDataGetLength(data) == RemoteToken.byteCount, let pointer = CFDataGetMutableBytePtr(data) else {
            return nil
        }
        token.bytes.indices.forEach { pointer[$0] = token.bytes[$0] }
        return data
    }
}
