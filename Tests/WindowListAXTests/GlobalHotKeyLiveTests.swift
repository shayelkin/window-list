import AppKit
import Carbon.HIToolbox
import PropertyBased
import Testing
import WindowListCore

private let presses = Gen.int(in: 1...3)

extension LiveAXTests {
    /// Registers real system-wide shortcuts and types them through the HID event tap.
    @MainActor @Suite struct HotKeys {
        /// ⌃⇧⌘B: a second shortcut on the same key, to tell registrations apart.
        static let other = try! HotKeyCombination(
            keyCode: CGKeyCode(kVK_ANSI_B), modifiers: [.command, .control, .shift])

        final class Counter {
            var count = 0
        }

        func register(_ combination: HotKeyCombination, _ counter: Counter) throws -> GlobalHotKey {
            do {
                return try GlobalHotKey(combination) { counter.count += 1 }
            } catch {
                Issue.record(
                    "precondition: \(combination) must be free; quit WindowList and any app using ⌃⌘B: \(error)")
                throw error
            }
        }

        func press(_ combination: HotKeyCombination) throws {
            let source = CGEventSource(stateID: .hidSystemState)
            let down = try #require(
                CGEvent(keyboardEventSource: source, virtualKey: combination.keyCode, keyDown: true),
                "key-down event for \(combination) must be creatable")
            let up = try #require(
                CGEvent(keyboardEventSource: source, virtualKey: combination.keyCode, keyDown: false),
                "key-up event for \(combination) must be creatable")
            down.flags = combination.eventFlags
            up.flags = combination.eventFlags
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        /// Hot key events reach Carbon handlers only while the app's event loop runs, which `swift test` doesn't do.
        func pump(for duration: Duration) {
            _ = NSApplication.shared
            let deadline = ContinuousClock.now.advanced(by: duration)
            while ContinuousClock.now < deadline {
                guard
                    let event = NSApp.nextEvent(
                        matching: .any, until: Date(timeIntervalSinceNow: 0.05), inMode: .default, dequeue: true)
                else { continue }
                NSApp.sendEvent(event)
            }
        }

        @Test func eachPressRunsActionOnce() async {
            await propertyCheck(count: 5, input: presses) { count in
                await Live.failOnThrow {
                    try Live.requireTrust()
                    let counter = Counter()
                    let hotKey = try register(.toggleList, counter)
                    try (0..<count).forEach { _ in try press(.toggleList) }
                    pump(for: .seconds(1))
                    #expect(counter.count == count, "\(count) presses of ⌃⌘B must run the action \(count) times")
                    withExtendedLifetime(hotKey) {}
                }
            }
        }

        @Test func pressRunsOnlyMatchingAction() async {
            await propertyCheck(count: 5, input: Gen.bool) { pressToggle in
                await Live.failOnThrow {
                    try Live.requireTrust()
                    let toggle = Counter()
                    let other = Counter()
                    let hotKeys = try [register(.toggleList, toggle), register(Self.other, other)]
                    let pressed = pressToggle ? HotKeyCombination.toggleList : Self.other
                    try press(pressed)
                    pump(for: .seconds(1))
                    #expect(
                        (toggle.count, other.count) == (pressToggle ? (1, 0) : (0, 1)),
                        "pressing \(pressed) must run only its own action; ran ⌃⌘B \(toggle.count), ⌃⇧⌘B \(other.count)"
                    )
                    withExtendedLifetime(hotKeys) {}
                }
            }
        }

        @Test func duplicateRegistrationFails() async throws {
            try Live.requireTrust()
            let first = try register(.toggleList, Counter())
            #expect(
                throws: HotKeyError.registerFailed(OSStatus(eventHotKeyExistsErr)),
                "registering ⌃⌘B while it is already registered must fail"
            ) { try GlobalHotKey(.toggleList) {} }
            withExtendedLifetime(first) {}
        }

        @Test func releasingFreesCombination() async throws {
            try Live.requireTrust()
            _ = try register(.toggleList, Counter())
            #expect(throws: Never.self, "⌃⌘B must be registrable again once the previous GlobalHotKey is released") {
                _ = try GlobalHotKey(.toggleList) {}
            }
        }
    }
}
