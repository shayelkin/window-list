import AXTestSupport
import AppKit
import ApplicationServices
import PropertyBased
import Testing
import WindowListCore

enum Live {
    static let timeout: Duration = .seconds(5)

    /// A sweep covers about 50 000 element ids per second and finds a fixture's windows below id 50, so a miss
    /// within this budget has covered the id range a hit would lie in a thousand times over.
    static let sweepBudget: Duration = .seconds(1)

    /// Shared like the app's single enumerator: its cache spares every test the cold snapshot, which sweeps each
    /// other app's windows for the whole budget. Fixture windows are new per test, so tests stay independent.
    static let defaultEnumerator = WindowEnumerator()
    static let sweepingEnumerator = WindowEnumerator(bruteForceBudget: sweepBudget)

    /// swift-property-based 2.0.1 discards errors thrown by a `propertyCheck` body (`try?` in IssueCounting.swift), so
    /// only recorded issues fail a check. Bodies that can throw run through this so a thrown error fails the test.
    static func failOnThrow(
        sourceLocation: SourceLocation = #_sourceLocation, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
        } catch is ExpectationFailedError {
            return
        } catch {
            Issue.record(error, "check threw instead of completing", sourceLocation: sourceLocation)
        }
    }

    static let title = Gen<Character>.oneOf(
        Gen.character(in: "a"..."z"),
        Gen.character(in: "A"..."Z"),
        Gen.character(in: "0"..."9"),
        Gen.character(in: "α"..."ω"),
        Gen.character(in: "あ"..."ん")
    ).string(of: 0...12)

    static let nonEmptyTitle = title.filter { !$0.isEmpty }

    static func requireTrust() throws {
        try #require(
            AXIsProcessTrusted(),
            """
            precondition: this process must be trusted for Accessibility. Grant the terminal app that runs \
            `swift test` access in System Settings › Privacy & Security › Accessibility.
            """
        )
    }

    /// Polls `produce` until `accept` holds or `timeout` passes; returns the last value either way.
    static func eventually<T>(
        timeout: Duration = Live.timeout,
        _ produce: () async throws -> T,
        until accept: (T) -> Bool
    ) async rethrows -> T {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var value = try await produce()
        while !accept(value), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
            value = try await produce()
        }
        return value
    }

    static func appName(of fixture: Fixture) -> String {
        NSRunningApplication(processIdentifier: fixture.process.rawValue)?.localizedName ?? ""
    }

    static func entries(of fixture: Fixture, in enumerator: WindowEnumerator) async -> [WindowEntry] {
        await enumerator.snapshot().filter { $0.process == fixture.process }
    }

    static func isOnscreen(_ window: WindowID) -> Bool {
        let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], window.rawValue) as? [[String: Any]]
        return info?.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    static func axWindowIDs(of fixture: Fixture) -> Set<WindowID> {
        Set(((try? AXApplication(process: fixture.process).windows()) ?? []).compactMap(\.windowID))
    }

    static func axElement(of window: WindowID, in fixture: Fixture) -> AXElement? {
        ((try? AXApplication(process: fixture.process).windows()) ?? []).first { $0.windowID == window }
    }

    static func focusedProcess() -> ProcessID? {
        (try? AXApplication.systemWide.element(kAXFocusedApplicationAttribute))?.processID
    }

    static func focusedWindow(of fixture: Fixture) -> WindowID? {
        (try? AXApplication(process: fixture.process).element.element(kAXFocusedWindowAttribute))?.windowID
    }

    static func isMinimized(_ window: WindowID, in fixture: Fixture) -> Bool? {
        guard let element = axElement(of: window, in: fixture) else { return nil }
        return try? element.bool(kAXMinimizedAttribute)
    }
}

extension Live {
    /// Services main-run-loop sources (AX observer callbacks) briefly; synchronous because the CF call is
    /// unavailable from async contexts.
    @MainActor static func spinMainRunLoop(seconds: CFTimeInterval = 0.05) {
        CFRunLoopRunInMode(.defaultMode, seconds, false)
    }
}
