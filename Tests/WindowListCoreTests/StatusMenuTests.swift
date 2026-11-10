import AppKit
import PropertyBased
import Testing
import WindowListCore

private let rightClicks: [NSEvent.EventType] = [.rightMouseDown, .rightMouseUp]
private let otherEvents: [NSEvent.EventType] = [
    .leftMouseDown, .leftMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
    .mouseMoved, .keyDown, .keyUp, .flagsChanged, .scrollWheel, .appKitDefined, .systemDefined,
]

/// Receives the toggle item's action in tests.
private final class Target: NSObject {
    @objc func toggle(_ sender: Any?) {}
}

@Suite struct StatusItemClickTests {
    @Test func rightClickOpensMenu() async {
        await propertyCheck(input: Gen.element(of: rightClicks).compactMap { $0 }) { type in
            #expect(StatusItemClick(type) == .menu, "a \(type) event on the menu bar icon must open the menu")
        }
    }

    @Test func otherEventsToggle() async {
        await propertyCheck(input: Gen.element(of: otherEvents).compactMap { $0 }) { type in
            #expect(StatusItemClick(type) == .toggle, "a \(type) event on the menu bar icon must toggle the panel")
        }
    }
}

@MainActor @Suite struct StatusMenuTests {
    @Test func toggleItemTitleFollowsVisibility() async {
        await propertyCheck(input: Gen.bool) { visible in
            let menu = StatusMenu.make(panelVisible: visible, toggle: #selector(Target.toggle), target: Target())
            let expected = visible ? StatusMenu.hideTitle : StatusMenu.showTitle
            #expect(
                menu.items.first?.title == expected,
                "with the panel visible=\(visible) the first item must read \(expected); got \(menu.items.map(\.title))"
            )
        }
    }

    @Test func toggleItemSendsToggleToTarget() async {
        await propertyCheck(input: Gen.bool) { visible in
            let target = Target()
            let menu = StatusMenu.make(panelVisible: visible, toggle: #selector(Target.toggle), target: target)
            let item = menu.items.first
            #expect(
                item?.action == #selector(Target.toggle) && item?.target === target,
                "the first item must send toggle(_:) to the given target, not \(String(describing: item?.action))"
            )
        }
    }

    @Test func lastItemQuitsApp() async {
        await propertyCheck(input: Gen.bool) { visible in
            let menu = StatusMenu.make(panelVisible: visible, toggle: #selector(Target.toggle), target: Target())
            let item = menu.items.last
            #expect(
                item?.title == StatusMenu.quitTitle
                    && item?.action == #selector(NSApplication.terminate(_:))
                    && item?.target === NSApplication.shared,
                "the last item must be \(StatusMenu.quitTitle) sending terminate(_:) to the app; got \(menu.items)"
            )
        }
    }

    @Test func itemsAreToggleSeparatorQuit() async {
        await propertyCheck(input: Gen.bool) { visible in
            let menu = StatusMenu.make(panelVisible: visible, toggle: #selector(Target.toggle), target: Target())
            #expect(
                menu.items.map(\.isSeparatorItem) == [false, true, false],
                "the menu must be exactly toggle, separator, quit; got \(menu.items.map(\.title))"
            )
        }
    }
}
