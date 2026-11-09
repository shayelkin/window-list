import ApplicationServices
import CoreGraphics
import Foundation
import WindowListCore

public enum SpaceDirection: Sendable, CustomStringConvertible {
    case left, right

    public var opposite: SpaceDirection {
        switch self {
        case .left: .right
        case .right: .left
        }
    }

    var hotKey: SpaceSwitchHotKey {
        switch self {
        case .left: .moveLeft
        case .right: .moveRight
        }
    }

    public var description: String {
        switch self {
        case .left: "left"
        case .right: "right"
        }
    }
}

public enum SpacesError: Error, CustomStringConvertible {
    case noDisplayInfo
    case mainDisplayNotFound(main: String, available: [String])
    case tooFewSpaces(DisplaySpaces)
    case currentSpaceNotInList(DisplaySpaces)
    case hotKey(SpaceSwitchHotKey, HotKeyParseError)
    case eventCreationFailed
    case didNotSwitch(direction: SpaceDirection, hotKey: SymbolicHotKey, from: SpaceID)
    case couldNotRestore(target: SpaceID, current: SpaceID?)

    public var description: String {
        switch self {
        case .noDisplayInfo:
            "CGSCopyManagedDisplaySpaces returned no usable display information"
        case .mainDisplayNotFound(let main, let available):
            "main display \(main) not found among managed displays \(available)"
        case .tooFewSpaces(let spaces):
            "precondition: the main display needs at least 2 desktop Spaces (found \(spaces)); "
                + "add one in Mission Control"
        case .currentSpaceNotInList(let spaces):
            "the main display's current Space is not a desktop Space (\(spaces)); leave full-screen apps first"
        case .hotKey(let hotKey, let error):
            "precondition: \(hotKey) must be enabled in System Settings › Keyboard › Keyboard Shortcuts › "
                + "Mission Control (read failed: \(error))"
        case .eventCreationFailed:
            "could not create keyboard CGEvents"
        case .didNotSwitch(let direction, let hotKey, let from):
            "posting the configured \(direction) Space shortcut (\(hotKey)) did not leave \(from) within "
                + "\(Spaces.switchTimeout); ensure the shortcut works and the pointer is on the main display"
        case .couldNotRestore(let target, let current):
            "could not return to \(target) (now on \(String(describing: current)))"
        }
    }
}

public enum Spaces {
    public static let switchTimeout: Duration = .seconds(3)
    /// Time for the Space-switch animation to finish before the next switch or window operation.
    public static let settleTime: Duration = .milliseconds(900)

    private static var mainDisplayIdentifier: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }

    public static func mainDisplaySpaces() throws(SpacesError) -> DisplaySpaces {
        let displays = SpaceTopology.displays()
        guard let first = displays.first else { throw .noDisplayInfo }
        guard displays.count > 1 else { return first }
        let main = mainDisplayIdentifier ?? "?"
        guard let display = displays.first(where: { $0.display.caseInsensitiveCompare(main) == .orderedSame }) else {
            throw .mainDisplayNotFound(main: main, available: displays.map(\.display))
        }
        return display
    }

    /// Requires ≥2 desktop Spaces on the main display, with the current one among them.
    public static func requireMultipleSpaces() throws(SpacesError) -> DisplaySpaces {
        let spaces = try mainDisplaySpaces()
        guard spaces.userSpaces.count >= 2 else { throw .tooFewSpaces(spaces) }
        guard spaces.userSpaces.contains(spaces.current) else { throw .currentSpaceNotInList(spaces) }
        return spaces
    }

    public static func activeSpace() -> SpaceID? { try? mainDisplaySpaces().current }

    /// The neighbouring desktop Space: right, or left when already on the last one.
    public static func neighbor(in spaces: DisplaySpaces) -> (direction: SpaceDirection, space: SpaceID)? {
        guard let index = spaces.userSpaces.firstIndex(of: spaces.current) else { return nil }
        let next = spaces.userSpaces.index(after: index)
        if next < spaces.userSpaces.endIndex { return (.right, spaces.userSpaces[next]) }
        guard index > spaces.userSpaces.startIndex else { return nil }
        return (.left, spaces.userSpaces[spaces.userSpaces.index(before: index)])
    }

    /// Posts the user's configured Mission Control shortcut and waits until the active Space changes.
    @discardableResult
    public static func switchSpace(_ direction: SpaceDirection) async throws(SpacesError) -> SpaceID? {
        let hotKey: SymbolicHotKey
        switch SymbolicHotKey.read(direction.hotKey) {
        case .success(let value): hotKey = value
        case .failure(let error): throw .hotKey(direction.hotKey, error)
        }
        guard let origin = activeSpace() else { throw .noDisplayInfo }
        try post(hotKey)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: switchTimeout)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            guard let now = activeSpace(), now != origin else { continue }
            try? await Task.sleep(for: settleTime)
            return now
        }
        throw .didNotSwitch(direction: direction, hotKey: hotKey, from: origin)
    }

    /// Runs `body`, then always returns to the Space that was active before it.
    public static func withSpaceRestored<T>(_ body: () async throws -> T) async throws -> T {
        guard let origin = activeSpace() else { throw SpacesError.noDisplayInfo }
        do {
            let value = try await body()
            try await restore(origin)
            return value
        } catch {
            try? await restore(origin)
            throw error
        }
    }

    private static func restore(_ target: SpaceID) async throws(SpacesError) {
        let attempts = max((try? mainDisplaySpaces().userSpaces.count) ?? 1, 1)
        for _ in 0..<attempts {
            let spaces = try mainDisplaySpaces()
            guard spaces.current != target else { return }
            guard let from = spaces.userSpaces.firstIndex(of: spaces.current),
                let to = spaces.userSpaces.firstIndex(of: target)
            else { throw .couldNotRestore(target: target, current: spaces.current) }
            try await switchSpace(to < from ? .left : .right)
        }
        guard activeSpace() == target else { throw .couldNotRestore(target: target, current: activeSpace()) }
    }

    private static func post(_ hotKey: SymbolicHotKey) throws(SpacesError) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: hotKey.keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: hotKey.keyCode, keyDown: false)
        else { throw .eventCreationFailed }
        down.flags = hotKey.flags
        up.flags = hotKey.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
