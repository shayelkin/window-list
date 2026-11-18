import AppKit
import Carbon.HIToolbox

public enum HotKeyError: Error, Equatable, Sendable {
    case unsupportedModifiers(NSEvent.ModifierFlags.RawValue)
    /// Since macOS 15, `RegisterEventHotKey` rejects combinations whose only modifiers are Option and Shift.
    case needsCommandOrControl
    case installHandlerFailed(OSStatus)
    case registerFailed(OSStatus)
}

/// A key plus modifiers that can be registered as a system-wide shortcut.
public struct HotKeyCombination: Equatable, Sendable, CustomStringConvertible {
    public static let supportedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    /// Ctrl+Cmd+B: show or hide the window list.
    public static let toggleList = Self(
        validKeyCode: CGKeyCode(kVK_ANSI_B),
        modifiers: [.command, .control])

    public let keyCode: CGKeyCode
    public let modifiers: NSEvent.ModifierFlags

    public init(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) throws(HotKeyError) {
        guard modifiers.isSubset(of: Self.supportedModifiers) else {
            throw .unsupportedModifiers(modifiers.subtracting(Self.supportedModifiers).rawValue)
        }
        guard !modifiers.isDisjoint(with: [.command, .control]) else { throw .needsCommandOrControl }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private init(validKeyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = validKeyCode
        self.modifiers = modifiers
    }

    /// `modifiers` as the Carbon mask `RegisterEventHotKey` takes.
    public var carbonModifiers: UInt32 {
        let pairs: [(NSEvent.ModifierFlags, Int)] = [
            (.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey),
        ]
        return pairs.filter { modifiers.contains($0.0) }.reduce(0) { $0 | UInt32($1.1) }
    }

    /// `modifiers` as the flags of a key event typing this combination.
    public var eventFlags: CGEventFlags {
        let pairs: [(NSEvent.ModifierFlags, CGEventFlags)] = [
            (.command, .maskCommand), (.control, .maskControl), (.option, .maskAlternate), (.shift, .maskShift),
        ]
        return pairs.filter { modifiers.contains($0.0) }.reduce([]) { $0.union($1.1) }
    }

    public var description: String { "keyCode \(keyCode) modifiers 0x\(String(modifiers.rawValue, radix: 16))" }
}

/// A system-wide shortcut that runs `action` on the main thread while this object is alive.
@MainActor
public final class GlobalHotKey {
    /// Shared by every registration; the per-registration id tells them apart.
    private static let signature: OSType = 0x574C_7374  // 'WLst'
    private static var lastID: UInt32 = 0

    public let combination: HotKeyCombination
    private let id: UInt32
    private let action: @MainActor () -> Void
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    public init(_ combination: HotKeyCombination, action: @escaping @MainActor () -> Void) throws(HotKeyError) {
        Self.lastID += 1
        self.combination = combination
        self.id = Self.lastID
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(), Self.handle, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { throw .installHandlerFailed(installed) }
        let registered = RegisterEventHotKey(
            UInt32(combination.keyCode), combination.carbonModifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else {
            RemoveEventHandler(handler)
            handler = nil
            throw .registerFailed(registered)
        }
    }

    isolated deinit {
        UnregisterEventHotKey(hotKey)
        RemoveEventHandler(handler)
    }

    /// Carbon calls this on the main thread for every hot key press in the app; only this registration's id runs
    /// `action`, the rest pass on to the next handler.
    private static let handle: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var pressed = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
            MemoryLayout<EventHotKeyID>.size, nil, &pressed)
        guard status == noErr else { return status }
        guard pressed.signature == signature else { return OSStatus(eventNotHandledErr) }
        let pressedID = pressed.id
        let address = UInt(bitPattern: userData)
        return MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
            guard pressedID == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.action()
            return noErr
        }
    }
}
