import ApplicationServices

public enum AXFailure: Error, Equatable, Sendable {
    case error(AXError, attribute: String)
    case typeMismatch(attribute: String)
}

public enum AXRole: Hashable, Sendable {
    case window
    case application
    case button
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case kAXWindowRole: self = .window
        case kAXApplicationRole: self = .application
        case kAXButtonRole: self = .button
        default: self = .other(rawValue)
        }
    }
}

public enum AXSubrole: Hashable, Sendable {
    case standardWindow
    case dialog
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case kAXStandardWindowSubrole: self = .standardWindow
        case kAXDialogSubrole: self = .dialog
        default: self = .other(rawValue)
        }
    }
}

/// An `AXUIElement` handle. AX elements are immutable CF references that may be used from any thread.
public struct AXElement: @unchecked Sendable, Hashable {
    public let raw: AXUIElement

    public init(_ raw: AXUIElement) { self.raw = raw }

    public static func == (lhs: AXElement, rhs: AXElement) -> Bool { CFEqual(lhs.raw, rhs.raw) }
    public func hash(into hasher: inout Hasher) { hasher.combine(CFHash(raw)) }

    public var windowID: WindowID? { PrivateAPI.windowID(of: raw) }

    public var processID: ProcessID? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(raw, &pid) == .success else { return nil }
        return ProcessID(pid)
    }

    func copyValue(_ attribute: String) throws(AXFailure) -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(raw, attribute as CFString, &value)
        guard result == .success else { throw .error(result, attribute: attribute) }
        guard let value else { throw .typeMismatch(attribute: attribute) }
        return value
    }

    public func string(_ attribute: String) throws(AXFailure) -> String {
        let value = try copyValue(attribute)
        guard CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String else {
            throw .typeMismatch(attribute: attribute)
        }
        return string
    }

    public func bool(_ attribute: String) throws(AXFailure) -> Bool {
        let value = try copyValue(attribute)
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { throw .typeMismatch(attribute: attribute) }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }

    public func element(_ attribute: String) throws(AXFailure) -> AXElement {
        let value = try copyValue(attribute)
        guard let element = AXElement(value) else { throw .typeMismatch(attribute: attribute) }
        return element
    }

    public func elements(_ attribute: String) throws(AXFailure) -> [AXElement] {
        let value = try copyValue(attribute)
        guard CFGetTypeID(value) == CFArrayGetTypeID(), let array = value as? [CFTypeRef] else {
            throw .typeMismatch(attribute: attribute)
        }
        return array.compactMap(AXElement.init)
    }

    public func set(_ attribute: String, to value: Bool) throws(AXFailure) {
        let result = AXUIElementSetAttributeValue(raw, attribute as CFString, value as CFBoolean)
        guard result == .success else { throw .error(result, attribute: attribute) }
    }

    public func perform(_ action: String) throws(AXFailure) {
        let result = AXUIElementPerformAction(raw, action as CFString)
        guard result == .success else { throw .error(result, attribute: action) }
    }

    public func role() throws(AXFailure) -> AXRole { AXRole(rawValue: try string(kAXRoleAttribute)) }
    public func subrole() throws(AXFailure) -> AXSubrole { AXSubrole(rawValue: try string(kAXSubroleAttribute)) }

    private init?(_ value: CFTypeRef) {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        self.raw = unsafeDowncast(value, to: AXUIElement.self)
    }
}

public struct AXApplication: Sendable {
    public let process: ProcessID
    public let element: AXElement

    public init(process: ProcessID) {
        self.process = process
        self.element = AXElement(AXUIElementCreateApplication(process.rawValue))
    }

    /// Windows on the current Space only (`kAXWindowsAttribute` omits other Spaces).
    public func windows() throws(AXFailure) -> [AXElement] { try element.elements(kAXWindowsAttribute) }

    public static var systemWide: AXElement { AXElement(AXUIElementCreateSystemWide()) }
}

/// An AX element verified to be the `AXWindow` root of a specific window.
public struct AXWindow: Sendable, Hashable {
    public let id: WindowID
    public let element: AXElement

    /// Descendants report their containing window's id, so the role check is required, not just the id match
    /// (AltTab #5849 invariant: https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/AXUIElement.swift).
    public init?(validating element: AXElement, expected: WindowID) {
        guard element.windowID == expected, (try? element.role()) == .window else { return nil }
        self.id = expected
        self.element = element
    }
}
