import AXTestSupport
import ApplicationServices
import CoreFoundation
import PropertyBased
import Testing
import WindowListCore

/// Preconditions (each failing with a how-to-fix message, never skipped):
/// Accessibility permission; ≥2 desktop Spaces on the main display; the Mission Control "Move left/right a space"
/// shortcuts enabled (their configured keys are read from the system).
extension LiveAXTests {
    @MainActor @Suite struct MultiSpace {
        /// How the other-Space window's AX element came into existence before the test returns to the start Space.
        enum Exposure: Sendable {
            /// No client ever requested it.
            case unseen
            /// Listed by `kAXWindows` while its Space was shown.
            case listed
            /// Delivered by a `kAXWindowCreatedNotification` observer when created.
            case observed
        }

        struct Scenario {
            let fixture: Fixture
            let origin: SpaceID
            let other: SpaceID
            let window: WindowID
            let title: String
        }

        /// Opens a fixture window on a neighbouring Space, exposes it as requested, returns to the start Space, runs
        /// `body`, and always restores the start Space afterwards.
        func withOtherSpaceWindow(
            title: String, exposure: Exposure, _ body: (Scenario) async throws -> Void
        ) async throws {
            try Live.requireTrust()
            let spaces = try Spaces.requireMultipleSpaces()
            let neighbor = try #require(
                Spaces.neighbor(in: spaces), "a neighbouring desktop Space must exist in \(spaces)")
            let fixture = try Fixture()
            defer { fixture.terminate() }
            var created: [AXElement] = []
            let observer = WindowCreationObserver { process, element in
                guard process == fixture.process else { return }
                created.append(element)
            }
            defer { observer.stop() }
            if exposure == .observed { observer.sync([fixture.process]) }
            try await Spaces.withSpaceRestored {
                let landed = try await Spaces.switchSpace(neighbor.direction)
                try #require(
                    landed == neighbor.space,
                    "switching \(neighbor.direction) must reach \(neighbor.space); got \(String(describing: landed))")
                let window = try fixture.open(title: title)
                let placement = await Live.eventually(
                    { SpaceTopology.spaces(of: window) }, until: { $0 == [neighbor.space] })
                try #require(
                    placement == [neighbor.space],
                    "new window \(window) must open on \(neighbor.space); it is on \(placement)")
                switch exposure {
                case .unseen:
                    break
                case .listed:
                    let listed = await Live.eventually(
                        { Live.axWindowIDs(of: fixture) }, until: { $0.contains(window) })
                    try #require(
                        listed.contains(window),
                        "kAXWindows must list \(window) while its Space is shown; got \(listed)")
                case .observed:
                    let delivered = await pumpMainRunLoop(until: { created.contains(where: { $0.windowID == window }) })
                    try #require(
                        delivered, "kAXWindowCreated must be delivered for \(window); got \(created.map(\.windowID))")
                }
                let back = try await Spaces.switchSpace(neighbor.direction.opposite)
                try #require(
                    back == spaces.current,
                    "switching back must return to \(spaces.current); got \(String(describing: back))")
                try await body(
                    Scenario(
                        fixture: fixture, origin: spaces.current, other: neighbor.space, window: window, title: title)
                )
            }
        }

        func pumpMainRunLoop(timeout: Duration = Live.timeout, until condition: () -> Bool) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while !condition(), clock.now < deadline {
                Live.spinMainRunLoop()
                await Task.yield()
            }
            return condition()
        }

        func entry(for scenario: Scenario) async throws -> WindowEntry {
            let enumerator = WindowEnumerator(bruteForceBudget: .seconds(5))
            let entries = await Live.eventually(
                { await Live.entries(of: scenario.fixture, in: enumerator) },
                until: { $0.contains { $0.id == scenario.window } }
            )
            return try #require(
                entries.first { $0.id == scenario.window },
                "snapshot must include other-Space window \(scenario.window); got \(entries.map(\.id))"
            )
        }

        func activateAndExpectSpaceSwitch(_ exposure: Exposure) async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: exposure) { scenario in
                        try await WindowActivator.activate(try await entry(for: scenario))
                        let active = await Live.eventually({ Spaces.activeSpace() }, until: { $0 == scenario.other })
                        #expect(
                            active == scenario.other,
                            "activating \(exposure) window must switch to \(scenario.other); now on \(String(describing: active))"
                        )
                        try? await Task.sleep(for: Spaces.settleTime)
                    }
                }
            }
        }

        func activateAndExpectFocus(_ exposure: Exposure) async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: exposure) { scenario in
                        try await WindowActivator.activate(try await entry(for: scenario))
                        let focus = await Live.eventually(
                            { (Live.focusedProcess(), Live.focusedWindow(of: scenario.fixture)) },
                            until: { $0.0 == scenario.fixture.process && $0.1 == scenario.window }
                        )
                        #expect(
                            focus.0 == scenario.fixture.process,
                            "focused app must be the fixture; got \(String(describing: focus.0))")
                        #expect(
                            focus.1 == scenario.window,
                            "focused window must be \(scenario.window); got \(String(describing: focus.1))")
                        try? await Task.sleep(for: Spaces.settleTime)
                    }
                }
            }
        }

        func closeAndExpectRemoval(_ exposure: Exposure) async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: exposure) { scenario in
                        try await WindowCloser.close(try await entry(for: scenario))
                        let enumerator = WindowEnumerator(bruteForceBudget: .seconds(2))
                        let remaining = await Live.eventually(
                            { Set(await Live.entries(of: scenario.fixture, in: enumerator).map(\.id)) },
                            until: { !$0.contains(scenario.window) }
                        )
                        #expect(
                            !remaining.contains(scenario.window),
                            "closing \(exposure) window \(scenario.window) must remove it from the list; got \(remaining)"
                        )
                        try? await Task.sleep(for: Spaces.settleTime)
                    }
                }
            }
        }

        @Test func configuredMoveLeftHotKeyIsReadable() {
            let result = SymbolicHotKey.read(.moveLeft)
            #expect(
                (try? result.get()) != nil,
                "precondition: \(SpaceSwitchHotKey.moveLeft) must be enabled; read \(result)")
        }

        @Test func configuredMoveRightHotKeyIsReadable() {
            let result = SymbolicHotKey.read(.moveRight)
            #expect(
                (try? result.get()) != nil,
                "precondition: \(SpaceSwitchHotKey.moveRight) must be enabled; read \(result)")
        }

        @Test func mainDisplayHasMultipleSpaces() throws {
            let spaces = try Spaces.requireMultipleSpaces()
            #expect(spaces.userSpaces.count >= 2, "precondition: ≥2 desktop Spaces on the main display; got \(spaces)")
        }

        @Test func axWindowsOmitsOtherSpaceWindow() async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: .listed) { scenario in
                        let listed = Live.axWindowIDs(of: scenario.fixture)
                        #expect(
                            !listed.contains(scenario.window),
                            "kAXWindows must omit \(scenario.window) on hidden \(scenario.other); got \(listed)")
                    }
                }
            }
        }

        /// Fails while another AX client (WindowList itself, AltTab, …) observes window creation in every app: that
        /// exposes the fixture window, so it is no longer unseen. Quit such apps before running.
        @Test func bruteForceCannotResolveUnseenWindow() async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: .unseen) { scenario in
                        let found = WindowEnumerator.bruteForce(
                            process: scenario.fixture.process, wanted: [scenario.window], budget: .seconds(2)
                        ).found
                        #expect(
                            found.isEmpty,
                            "an unseen window has no AX element yet, so the sweep must not find \(scenario.window)")
                    }
                }
            }
        }

        @Test func bruteForceResolvesListedWindow() async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: .listed) { scenario in
                        let found = WindowEnumerator.bruteForce(
                            process: scenario.fixture.process, wanted: [scenario.window], budget: .seconds(5)
                        ).found
                        #expect(
                            found[scenario.window] != nil,
                            "the sweep must find listed window \(scenario.window) on hidden \(scenario.other)")
                    }
                }
            }
        }

        @Test func bruteForceResolvesObservedWindow() async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: .observed) { scenario in
                        let found = WindowEnumerator.bruteForce(
                            process: scenario.fixture.process, wanted: [scenario.window], budget: .seconds(5)
                        ).found
                        #expect(
                            found[scenario.window] != nil,
                            "the sweep must find observed window \(scenario.window) on hidden \(scenario.other)")
                    }
                }
            }
        }

        @Test func snapshotResolvesListedWindowWithTitle() async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: .listed) { scenario in
                        let entry = try await entry(for: scenario)
                        #expect(
                            entry.isResolved && entry.title == scenario.title,
                            "listed other-Space window must be resolved with title \"\(scenario.title)\"; got \(entry)"
                        )
                    }
                }
            }
        }

        /// Fails while another AX client (WindowList itself, AltTab, …) observes window creation in every app: that
        /// exposes the fixture window, so the snapshot resolves its title. Quit such apps before running.
        @Test func snapshotListsUnseenWindowByAppName() async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: .unseen) { scenario in
                        let entry = try await entry(for: scenario)
                        let appName = Live.appName(of: scenario.fixture)
                        #expect(
                            !entry.isResolved && entry.title == appName,
                            "unseen other-Space window must be unresolved and titled \"\(appName)\"; got \(entry)"
                        )
                    }
                }
            }
        }

        @Test func snapshotOmitsOrderedOutWindowOnHiddenSpace() async {
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withOtherSpaceWindow(title: title, exposure: .unseen) { scenario in
                        try scenario.fixture.orderOut(scenario.window)
                        let placement = SpaceTopology.spaces(of: scenario.window)
                        try #require(
                            placement == [scenario.other],
                            "ordered-out window \(scenario.window) must keep reporting \(scenario.other) (like apps' hidden windows); got \(placement)"
                        )
                        let enumerator = WindowEnumerator(bruteForceBudget: .seconds(2))
                        let entries = await Live.entries(of: scenario.fixture, in: enumerator)
                        #expect(
                            !entries.contains { $0.id == scenario.window },
                            "ordered-out window \(scenario.window) on hidden \(scenario.other) must not be listed; got \(entries)"
                        )
                    }
                }
            }
        }

        struct FullScreenScenario {
            let fixture: Fixture
            let window: WindowID
            let origin: SpaceID
        }

        /// Enters full screen with a fixture window and runs `body` on its full-screen Space. Always leaves full screen
        /// and waits until the start Space is shown and settled again, so the next test starts on a desktop.
        func withFullScreenWindow(title: String, _ body: (FullScreenScenario) async throws -> Void) async throws {
            try Live.requireTrust()
            let origin = try Spaces.requireMultipleSpaces().current
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let window = try fixture.open(title: title)
            let scenario = FullScreenScenario(fixture: fixture, window: window, origin: origin)
            let outcome: Result<Void, any Error>
            do {
                try fixture.setFullScreen(window, true)
                let left = await Live.eventually({ Spaces.activeSpace() }, until: { $0 != origin })
                try #require(
                    left != origin, "entering full screen must leave \(origin); still on \(String(describing: left))")
                try await body(scenario)
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            try? fixture.setFullScreen(window, false)
            try await returnTo(origin)
            try outcome.get()
        }

        func returnTo(_ origin: SpaceID) async throws {
            _ = await Live.eventually({ Spaces.activeSpace() }, until: { $0 == origin })
            try? await Task.sleep(for: Spaces.settleTime)
            let back = Spaces.activeSpace()
            try #require(
                back == origin, "leaving full screen must return to \(origin); now on \(String(describing: back))")
        }

        /// Opens a panel styled like the app's, in an accessory-policy fixture (as WindowList is an LSUIElement app).
        func withAppStylePanel(title: String, _ body: (WindowID) async throws -> Void) async throws {
            let host = try Fixture(accessory: true)
            defer { host.terminate() }
            let panel = try host.openPanel(title: title)
            let shown = await Live.eventually({ Live.isOnscreen(panel) }, until: { $0 })
            try #require(shown, "app-style panel \(panel) must be on screen on the start desktop")
            try await body(panel)
        }

        @Test func panelStaysOffFullScreenSpace() async {
            await propertyCheck(count: 2, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withAppStylePanel(title: title) { panel in
                        try await withFullScreenWindow(title: title) { _ in
                            try? await Task.sleep(for: Spaces.settleTime)
                            #expect(
                                !Live.isOnscreen(panel),
                                "app-style panel \(panel) must not appear on a full-screen Space")
                        }
                    }
                }
            }
        }

        @Test func panelReturnsAfterFullScreen() async {
            await propertyCheck(count: 2, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withAppStylePanel(title: title) { panel in
                        try await withFullScreenWindow(title: title) { _ in }
                        #expect(
                            Live.isOnscreen(panel),
                            "app-style panel \(panel) must be on screen again once the desktop is back")
                    }
                }
            }
        }

        @Test func panelJoinsOtherDesktopSpace() async {
            await propertyCheck(count: 2, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    try await withAppStylePanel(title: title) { panel in
                        let spaces = try Spaces.requireMultipleSpaces()
                        let neighbor = try #require(
                            Spaces.neighbor(in: spaces), "a neighbouring desktop Space must exist in \(spaces)")
                        try await Spaces.withSpaceRestored {
                            let landed = try await Spaces.switchSpace(neighbor.direction)
                            try #require(
                                landed == neighbor.space,
                                "switching \(neighbor.direction) must reach \(neighbor.space); got \(String(describing: landed))"
                            )
                            #expect(
                                Live.isOnscreen(panel),
                                "app-style panel \(panel) must follow to desktop \(neighbor.space)")
                        }
                    }
                }
            }
        }

        @Test func activateSwitchesToListedWindowSpace() async { await activateAndExpectSpaceSwitch(.listed) }
        @Test func activateFocusesListedWindow() async { await activateAndExpectFocus(.listed) }
        @Test func activateSwitchesToUnseenWindowSpace() async { await activateAndExpectSpaceSwitch(.unseen) }
        @Test func activateFocusesUnseenWindow() async { await activateAndExpectFocus(.unseen) }
        @Test func closeRemovesListedWindow() async { await closeAndExpectRemoval(.listed) }
        @Test func closeRemovesUnseenWindow() async { await closeAndExpectRemoval(.unseen) }
    }
}
