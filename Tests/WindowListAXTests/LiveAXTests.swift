import AXTestSupport
import AppKit
import ApplicationServices
import PropertyBased
import Testing
import WindowListCore

/// Drives real windows, focus and Spaces, so everything here runs serially.
@Suite(.serialized) struct LiveAXTests {}

extension LiveAXTests {
    @Suite struct CurrentSpace {
        @Test func axTrustIsGranted() throws {
            try Live.requireTrust()
        }

        @Test func axWindowsResolvesEveryFixtureWindow() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            await propertyCheck(count: 10, input: Live.title.array(of: 1...4)) { titles in
                await Live.failOnThrow {
                    let opened = Set(try titles.map { try fixture.open(title: $0) })
                    defer { opened.forEach { try? fixture.close($0) } }
                    let listed = await Live.eventually({ Live.axWindowIDs(of: fixture) }, until: opened.isSubset)
                    #expect(
                        opened.isSubset(of: listed), "kAXWindows must list every opened window \(opened); got \(listed)"
                    )
                }
            }
        }

        @Test func bruteForceFindsSameElementAsAXWindows() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            await propertyCheck(count: 10, input: Live.title.array(of: 1...4)) { titles in
                await Live.failOnThrow {
                    let opened = try titles.map { try fixture.open(title: $0) }
                    defer { opened.forEach { try? fixture.close($0) } }
                    _ = await Live.eventually({ Live.axWindowIDs(of: fixture) }, until: Set(opened).isSubset)
                    let swept = WindowEnumerator.bruteForce(
                        process: fixture.process, wanted: Set(opened), budget: .seconds(5)
                    ).found
                    let mismatched = opened.filter { swept[$0]?.element != Live.axElement(of: $0, in: fixture) }
                    #expect(mismatched.isEmpty, "remote-token sweep must find the kAXWindows element for \(mismatched)")
                }
            }
        }

        @Test func axWindowRejectsMismatchedWindowID() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            await propertyCheck(count: 10, input: Live.title, Live.title) { first, second in
                await Live.failOnThrow {
                    let a = try fixture.open(title: first)
                    let b = try fixture.open(title: second)
                    defer { [a, b].forEach { try? fixture.close($0) } }
                    let element = try #require(
                        await Live.eventually({ Live.axElement(of: a, in: fixture) }, until: { $0 != nil }),
                        "AX element for \(a) must appear"
                    )
                    #expect(
                        AXWindow(validating: element, expected: b) == nil, "\(a)'s element must not validate as \(b)")
                }
            }
        }

        @Test func axWindowRejectsNonWindowElement() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            await propertyCheck(count: 10, input: Live.title) { title in
                await Live.failOnThrow {
                    let window = try fixture.open(title: title)
                    defer { try? fixture.close(window) }
                    let element = try #require(
                        await Live.eventually({ Live.axElement(of: window, in: fixture) }, until: { $0 != nil }),
                        "AX element for \(window) must appear"
                    )
                    let button = try element.element(kAXCloseButtonAttribute)
                    #expect(
                        button.windowID == window,
                        "precondition: a descendant reports its containing window's id (\(String(describing: button.windowID)))"
                    )
                    #expect(
                        AXWindow(validating: button, expected: window) == nil,
                        "the close button must not validate as \(window)")
                }
            }
        }

        @Test func snapshotContainsExactlyFixtureTitles() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            let appName = Live.appName(of: fixture)
            await propertyCheck(count: 10, input: Live.title.array(of: 1...5)) { titles in
                await Live.failOnThrow {
                    let opened = try titles.map { try fixture.open(title: $0) }
                    defer { opened.forEach { try? fixture.close($0) } }
                    let expected = titles.map { $0.isEmpty ? appName : $0 }.sorted()
                    let listed = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator).map(\.title).sorted() },
                        until: { $0 == expected }
                    )
                    #expect(listed == expected, "snapshot titles for the fixture must be \(expected); got \(listed)")
                }
            }
        }

        @Test func snapshotExcludesUndersizedWindows() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            let side = Gen.double(in: 10...(WindowBounds.minimumSide - 1))
            await propertyCheck(count: 10, input: Live.nonEmptyTitle, side, Live.nonEmptyTitle) { tiny, side, normal in
                await Live.failOnThrow {
                    let small = try fixture.open(title: tiny, width: side, height: side, style: .borderless)
                    let large = try fixture.open(title: normal)
                    defer { [small, large].forEach { try? fixture.close($0) } }
                    let ids = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator).map(\.id) },
                        until: { $0.contains(large) }
                    )
                    #expect(ids.contains(large), "precondition: the regular window \(large) must be listed; got \(ids)")
                    #expect(!ids.contains(small), "\(side)pt window \(small) must not be listed; got \(ids)")
                }
            }
        }

        @Test func snapshotReportsMinimizedState() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            await propertyCheck(count: 5, input: Live.nonEmptyTitle, Live.nonEmptyTitle) { first, second in
                await Live.failOnThrow {
                    let minimized = try fixture.open(title: first)
                    let visible = try fixture.open(title: second)
                    defer { [minimized, visible].forEach { try? fixture.close($0) } }
                    try fixture.minimize(minimized)
                    let expected: [WindowID: Bool] = [minimized: true, visible: false]
                    let state = await Live.eventually(
                        {
                            await Live.entries(of: fixture, in: enumerator)
                                .reduce(into: [WindowID: Bool]()) { $0[$1.id] = $1.isMinimized }
                        },
                        until: { $0 == expected }
                    )
                    #expect(state == expected, "isMinimized must be \(expected); got \(state)")
                }
            }
        }

        @Test func snapshotDropsTerminatedProcess() async throws {
            try Live.requireTrust()
            let enumerator = Live.defaultEnumerator
            await propertyCheck(count: 3, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    let fixture = try Fixture()
                    defer { fixture.terminate() }
                    let window = try fixture.open(title: title)
                    let before = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator).map(\.id) }, until: { $0.contains(window) }
                    )
                    try #require(before.contains(window), "precondition: \(window) must be listed before termination")
                    fixture.terminate()
                    let after = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator) }, until: \.isEmpty
                    )
                    #expect(after.isEmpty, "a terminated process must have no entries; got \(after.map(\.title))")
                }
            }
        }

        @Test func activateFocusesChosenWindow() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            let input = zip(Live.nonEmptyTitle.array(of: 2...4), Gen.int(in: 0...3))
            await propertyCheck(count: 10, input: input) { titles, choice in
                await Live.failOnThrow {
                    let opened = try titles.map { try fixture.open(title: $0) }
                    defer { opened.forEach { try? fixture.close($0) } }
                    let target = try #require(
                        opened.isEmpty ? nil : opened[choice % opened.count],
                        "shrinking may drop below the generator's 2 titles; got \(titles)")
                    let entries = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator) },
                        until: { Set($0.map(\.id)).isSuperset(of: opened) }
                    )
                    let entry = try #require(
                        entries.first { $0.id == target }, "\(target) must be listed before activation")
                    try await WindowActivator.activate(entry)
                    let focus = await Live.eventually(
                        { (Live.focusedProcess(), Live.focusedWindow(of: fixture)) },
                        until: { $0.0 == fixture.process && $0.1 == target }
                    )
                    #expect(
                        focus.0 == fixture.process,
                        "focused app must be the fixture \(fixture.process); got \(String(describing: focus.0))")
                    #expect(focus.1 == target, "focused window must be \(target); got \(String(describing: focus.1))")
                }
            }
        }

        @Test func activateUnminimizesWindow() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            await propertyCheck(count: 5, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    let window = try fixture.open(title: title)
                    defer { try? fixture.close(window) }
                    try fixture.minimize(window)
                    let entries = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator) },
                        until: { $0.contains { $0.id == window && $0.isMinimized } }
                    )
                    let entry = try #require(
                        entries.first { $0.id == window && $0.isMinimized }, "\(window) must be listed as minimized"
                    )
                    try await WindowActivator.activate(entry)
                    let minimized = await Live.eventually(
                        { Live.isMinimized(window, in: fixture) }, until: { $0 == false })
                    #expect(
                        minimized == false,
                        "activating \(window) must unminimize it; kAXMinimized is \(String(describing: minimized))")
                }
            }
        }

        @Test func closeRemovesChosenWindow() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            let input = zip(Live.nonEmptyTitle.array(of: 2...4), Gen.int(in: 0...3))
            await propertyCheck(count: 10, input: input) { titles, choice in
                await Live.failOnThrow {
                    let opened = try titles.map { try fixture.open(title: $0) }
                    defer { opened.forEach { try? fixture.close($0) } }
                    let target = try #require(
                        opened.isEmpty ? nil : opened[choice % opened.count],
                        "shrinking may drop below the generator's 2 titles; got \(titles)")
                    let entries = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator) },
                        until: { Set($0.map(\.id)).isSuperset(of: opened) }
                    )
                    let entry = try #require(
                        entries.first { $0.id == target }, "\(target) must be listed before closing")
                    try await WindowCloser.close(entry)
                    let remaining = await Live.eventually(
                        { Set(await Live.entries(of: fixture, in: enumerator).map(\.id)) },
                        until: { !$0.contains(target) }
                    )
                    #expect(!remaining.contains(target), "closed window \(target) must not be listed; got \(remaining)")
                }
            }
        }

        @Test func closeKeepsOtherWindows() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            let input = zip(Live.nonEmptyTitle.array(of: 2...4), Gen.int(in: 0...3))
            await propertyCheck(count: 10, input: input) { titles, choice in
                await Live.failOnThrow {
                    let opened = try titles.map { try fixture.open(title: $0) }
                    defer { opened.forEach { try? fixture.close($0) } }
                    let target = try #require(
                        opened.isEmpty ? nil : opened[choice % opened.count],
                        "shrinking may drop below the generator's 2 titles; got \(titles)")
                    let entries = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator) },
                        until: { Set($0.map(\.id)).isSuperset(of: opened) }
                    )
                    let entry = try #require(
                        entries.first { $0.id == target }, "\(target) must be listed before closing")
                    try await WindowCloser.close(entry)
                    let others = Set(opened).subtracting([target])
                    let remaining = await Live.eventually(
                        { Set(await Live.entries(of: fixture, in: enumerator).map(\.id)) },
                        until: { !$0.contains(target) }
                    )
                    #expect(
                        others.isSubset(of: remaining),
                        "closing \(target) must keep \(others) listed; got \(remaining)")
                }
            }
        }

        @Test func closeRemovesMinimizedWindow() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            let enumerator = Live.defaultEnumerator
            await propertyCheck(count: 5, input: Live.nonEmptyTitle) { title in
                await Live.failOnThrow {
                    let window = try fixture.open(title: title)
                    defer { try? fixture.close(window) }
                    try fixture.minimize(window)
                    let entries = await Live.eventually(
                        { await Live.entries(of: fixture, in: enumerator) },
                        until: { $0.contains { $0.id == window && $0.isMinimized } }
                    )
                    let entry = try #require(
                        entries.first { $0.id == window && $0.isMinimized }, "\(window) must be listed as minimized"
                    )
                    try await WindowCloser.close(entry)
                    let remaining = await Live.eventually(
                        { Set(await Live.entries(of: fixture, in: enumerator).map(\.id)) },
                        until: { !$0.contains(window) }
                    )
                    #expect(
                        !remaining.contains(window),
                        "closed minimized window \(window) must not be listed; got \(remaining)")
                }
            }
        }
    }
}

extension LiveAXTests {
    @MainActor @Suite struct CreationObserver {
        @Test func observerReportsNewWindow() async throws {
            try Live.requireTrust()
            let fixture = try Fixture()
            defer { fixture.terminate() }
            var created: [AXElement] = []
            let observer = WindowCreationObserver { process, element in
                guard process == fixture.process else { return }
                created.append(element)
            }
            defer { observer.stop() }
            observer.sync([fixture.process])
            await propertyCheck(count: 5, input: Live.title) { title in
                await Live.failOnThrow {
                    let window = try fixture.open(title: title)
                    defer { try? fixture.close(window) }
                    let clock = ContinuousClock()
                    let deadline = clock.now.advanced(by: Live.timeout)
                    while !created.contains(where: { $0.windowID == window }), clock.now < deadline {
                        Live.spinMainRunLoop()
                        await Task.yield()
                    }
                    #expect(
                        created.contains(where: { $0.windowID == window }),
                        "kAXWindowCreated must report \(window); got \(created.map(\.windowID))")
                }
            }
        }

        @Test func syncObservesExactlyRequestedProcesses() async throws {
            try Live.requireTrust()
            let fixtures = [try Fixture(), try Fixture()]
            defer { fixtures.forEach { $0.terminate() } }
            let observer = WindowCreationObserver { _, _ in }
            defer { observer.stop() }
            await propertyCheck(count: 20, input: Gen.bool.array(of: 2)) { mask in
                await Live.failOnThrow {
                    let requested = Set(zip(fixtures, mask).filter(\.1).map(\.0.process))
                    observer.sync(requested)
                    #expect(
                        observer.observedProcesses == requested,
                        "observed \(observer.observedProcesses) must equal requested \(requested)")
                }
            }
        }
    }
}
