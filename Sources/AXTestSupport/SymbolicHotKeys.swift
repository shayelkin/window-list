import CoreFoundation
import CoreGraphics

/// Mission Control shortcut ids in `com.apple.symbolichotkeys` (community-documented, e.g.
/// https://gist.github.com/mattrighetti/24b02c00c8a3a53966bc04f7305f99aa).
public enum SpaceSwitchHotKey: Int, Sendable, CustomStringConvertible {
    case moveLeft = 79
    case moveRight = 81

    public var description: String {
        switch self {
        case .moveLeft: "Mission Control › \"Move left a space\" (symbolic hotkey 79)"
        case .moveRight: "Mission Control › \"Move right a space\" (symbolic hotkey 81)"
        }
    }
}

public enum HotKeyParseError: Error, Equatable, Sendable {
    case missing
    case disabled
    case wrongType(String)
    case unsupportedType(String)
    case badParameterCount(Int)
    case keyCodeOutOfRange(Int)
    case unknownModifierBits(UInt64)
}

public struct SymbolicHotKey: Equatable, Sendable, CustomStringConvertible {
    public static let maximumKeyCode = 0x7F
    public static let supportedModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskNumericPad, .maskSecondaryFn,
    ]

    public let keyCode: CGKeyCode
    public let flags: CGEventFlags

    public var description: String { "keyCode \(keyCode) flags 0x\(String(flags.rawValue, radix: 16))" }

    /// Parses one `AppleSymbolicHotKeys` entry:
    /// `{enabled = 1; value = {type = standard; parameters = (ascii, keyCode, modifierMask)}}`.
    public static func parse(_ entry: Any?) -> Result<SymbolicHotKey, HotKeyParseError> {
        guard let entry else { return .failure(.missing) }
        guard let dictionary = entry as? [String: Any] else { return .failure(.wrongType("entry")) }
        guard let enabled = dictionary["enabled"] as? Bool else { return .failure(.wrongType("enabled")) }
        guard enabled else { return .failure(.disabled) }
        guard let value = dictionary["value"] as? [String: Any] else { return .failure(.wrongType("value")) }
        guard let type = value["type"] as? String else { return .failure(.wrongType("value.type")) }
        guard type == "standard" else { return .failure(.unsupportedType(type)) }
        guard let parameters = value["parameters"] as? [Any] else {
            return .failure(.wrongType("value.parameters"))
        }
        guard parameters.count == 3 else { return .failure(.badParameterCount(parameters.count)) }
        let integers = parameters.compactMap { $0 as? Int }
        guard integers.count == parameters.count else { return .failure(.wrongType("value.parameters[]")) }
        let rawKeyCode = integers[1]
        guard (0...maximumKeyCode).contains(rawKeyCode), let keyCode = CGKeyCode(exactly: rawKeyCode) else {
            return .failure(.keyCodeOutOfRange(rawKeyCode))
        }
        guard let mask = UInt64(exactly: integers[2]) else {
            return .failure(.wrongType("value.parameters[2]"))
        }
        let unknown = mask & ~supportedModifiers.rawValue
        guard unknown == 0 else { return .failure(.unknownModifierBits(unknown)) }
        return .success(SymbolicHotKey(keyCode: keyCode, flags: CGEventFlags(rawValue: mask)))
    }

    /// Reads the user's configured binding; never assumes the default.
    public static func read(_ hotKey: SpaceSwitchHotKey) -> Result<SymbolicHotKey, HotKeyParseError> {
        let value = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString
        )
        guard let value else { return .failure(.missing) }
        guard let all = value as? [String: Any] else { return .failure(.wrongType("AppleSymbolicHotKeys")) }
        return parse(all[String(hotKey.rawValue)])
    }
}
