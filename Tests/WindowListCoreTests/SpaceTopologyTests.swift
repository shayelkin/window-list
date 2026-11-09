import PropertyBased
import Testing
import WindowListCore

private struct SpaceFields: Sendable {
    let id: Int
    let type: Int

    var dictionary: [String: Any] { ["ManagedSpaceID": id, "type": type, "uuid": "u\(id)"] }
}

private struct DisplayFields: Sendable, CustomStringConvertible {
    let display: String
    let current: Int
    let spaces: [SpaceFields]

    var dictionary: [String: Any] {
        [
            "Display Identifier": display,
            "Current Space": ["ManagedSpaceID": current, "type": 0],
            "Spaces": spaces.map(\.dictionary),
        ]
    }

    var expectedUserSpaces: [UInt64] {
        spaces.filter { $0.type == SpaceTopology.userSpaceType }.map { UInt64($0.id) }
    }

    var description: String {
        "\(display) current \(current) spaces \(spaces.map { ($0.id, $0.type) })"
    }
}

private let spaceFields = zip(Gen.int(in: 1...100_000), Gen.element(of: [0, 0, 0, 4]).compactMap { $0 })
    .map { SpaceFields(id: $0, type: $1) }

private let displayFields = zip(
    Gen.character(in: "A"..."F").string(of: 1...8),
    Gen.int(in: 1...100_000),
    spaceFields.array(of: 0...8)
).map { DisplayFields(display: $0, current: $1, spaces: $2) }

private let spaceSet = Gen.uint64(in: 1...20).compactMap { SpaceID($0) }.set(ofAtMost: 0...6)

private enum DisplayKey: CaseIterable, Sendable {
    case identifier, current, spaces

    var name: String {
        switch self {
        case .identifier: "Display Identifier"
        case .current: "Current Space"
        case .spaces: "Spaces"
        }
    }
}

@Suite struct SpaceTopologyTests {
    @Test func parsesEveryWellFormedDisplay() async {
        await propertyCheck(count: 500, input: displayFields.array(of: 0...4)) { displays in
            let parsed = SpaceTopology.parse(displays.map(\.dictionary))
            #expect(parsed.count == displays.count, "every well-formed display must parse: \(displays) -> \(parsed)")
        }
    }

    @Test func keepsOnlyUserSpacesInOrder() async {
        await propertyCheck(count: 500, input: displayFields) { display in
            let parsed = SpaceTopology.parse([display.dictionary]).first
            let actual = parsed?.userSpaces.map(\.rawValue)
            #expect(
                actual == display.expectedUserSpaces,
                "user Spaces of \(display) must be \(display.expectedUserSpaces), got \(String(describing: actual))")
        }
    }

    @Test func readsCurrentSpaceAndIdentifier() async {
        await propertyCheck(count: 500, input: displayFields) { display in
            let parsed = SpaceTopology.parse([display.dictionary]).first
            #expect(
                parsed?.current.rawValue == UInt64(display.current) && parsed?.display == display.display,
                "parsed \(String(describing: parsed)) must carry current Space and identifier of \(display)"
            )
        }
    }

    @Test func dropsDisplayMissingAKey() async {
        await propertyCheck(count: 500, input: displayFields, Gen<DisplayKey>.case) { display, key in
            var dictionary = display.dictionary
            dictionary[key.name] = nil
            let parsed = SpaceTopology.parse([dictionary])
            #expect(parsed.isEmpty, "display without \(key.name) must be dropped, got \(parsed)")
        }
    }

    @Test func dropsDisplayWithMistypedKey() async {
        await propertyCheck(count: 500, input: displayFields, Gen<DisplayKey>.case) { display, key in
            var dictionary = display.dictionary
            dictionary[key.name] = 17
            let parsed = SpaceTopology.parse([dictionary])
            #expect(parsed.isEmpty, "display with non-conforming \(key.name) must be dropped, got \(parsed)")
        }
    }

    @Test func dropsDisplayWithInvalidCurrentSpace() async {
        await propertyCheck(count: 500, input: displayFields, Gen.int(in: Int.min...0)) { display, current in
            var dictionary = display.dictionary
            dictionary["Current Space"] = ["ManagedSpaceID": current]
            let parsed = SpaceTopology.parse([dictionary])
            #expect(parsed.isEmpty, "current Space id \(current) must be rejected, got \(parsed)")
        }
    }

    @Test func skipsMalformedSpaces() async {
        await propertyCheck(count: 500, input: displayFields, Gen.int(in: Int.min...0)) { display, badID in
            var dictionary = display.dictionary
            let malformed: [[String: Any]] = [
                ["type": 0], ["ManagedSpaceID": badID, "type": 0], ["ManagedSpaceID": "x", "type": 0],
            ]
            dictionary["Spaces"] = display.spaces.map(\.dictionary) + malformed
            let actual = SpaceTopology.parse([dictionary]).first?.userSpaces.map(\.rawValue)
            #expect(
                actual == display.expectedUserSpaces,
                "malformed Spaces must be skipped; got \(String(describing: actual))")
        }
    }

    @Test func unresolvedOnNoSpaceIsNotListed() async {
        await propertyCheck(count: 500, input: spaceSet) { current in
            #expect(
                !SpaceTopology.shouldListUnresolved(windowSpaces: [], currentSpaces: current, isOrderedIn: true),
                "a window on no Space (ordered out) must not be listed"
            )
        }
    }

    @Test func unresolvedOnShownSpaceIsNotListed() async {
        await propertyCheck(count: 500, input: spaceSet, spaceSet) { windowSpaces, others in
            guard let shown = windowSpaces.first else { return }
            #expect(
                !SpaceTopology.shouldListUnresolved(
                    windowSpaces: windowSpaces, currentSpaces: others.union([shown]), isOrderedIn: true),
                "a window on shown Space \(shown) is authoritatively absent from kAXWindows and must not be listed"
            )
        }
    }

    @Test func unresolvedOnlyOnHiddenSpacesIsListed() async {
        await propertyCheck(count: 500, input: spaceSet, spaceSet) { windowSpaces, current in
            let hidden = windowSpaces.subtracting(current)
            guard !hidden.isEmpty else { return }
            #expect(
                SpaceTopology.shouldListUnresolved(windowSpaces: hidden, currentSpaces: current, isOrderedIn: true),
                "a window only on hidden Spaces \(hidden) (shown: \(current)) must be listed"
            )
        }
    }

    @Test func unresolvedOrderedOutIsNeverListed() async {
        await propertyCheck(count: 500, input: spaceSet, spaceSet) { windowSpaces, current in
            #expect(
                !SpaceTopology.shouldListUnresolved(
                    windowSpaces: windowSpaces, currentSpaces: current, isOrderedIn: false),
                "an ordered-out window (on \(windowSpaces), shown: \(current)) is invisible and must not be listed"
            )
        }
    }

}

@Suite struct UnresolvedEntryTests {
    @Test func unresolvedEntryUsesAppNameAsTitle() async {
        await propertyCheck(count: 500, input: Generators.windowID, Generators.processID, Generators.text) {
            id, process, app in
            let entry = WindowEntry(unresolved: id, process: process, appName: app)
            #expect(
                entry.title == app,
                "unseen window title must fall back to the app name \"\(app)\", got \"\(entry.title)\"")
        }
    }

    @Test func unresolvedEntryIsNotResolved() async {
        await propertyCheck(count: 500, input: Generators.windowID, Generators.processID, Generators.text) {
            id, process, app in
            let entry = WindowEntry(unresolved: id, process: process, appName: app)
            #expect(
                !entry.isResolved && !entry.isMinimized, "unseen entry must be unresolved and not minimized: \(entry)")
        }
    }
}
