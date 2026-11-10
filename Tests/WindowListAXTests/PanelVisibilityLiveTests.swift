import AppKit
import PropertyBased
import Testing
import WindowListCore

private let toggles = Gen.int(in: 0...8)

extension LiveAXTests {
    /// Toggles a real in-process panel styled like the app's, so visibility comes from the window server.
    @MainActor @Suite struct PanelToggling {
        func withPanel(visible: Bool, _ body: (NSPanel) throws -> Void) rethrows {
            _ = NSApplication.shared
            let panel = NSPanel(
                contentRect: NSRect(x: 100, y: 100, width: 320, height: 240),
                styleMask: PanelStyle.styleMask,
                backing: .buffered,
                defer: false
            )
            PanelStyle.apply(to: panel)
            panel.isReleasedWhenClosed = false
            if visible { panel.orderFrontRegardless() }
            defer { panel.close() }
            try body(panel)
        }

        @Test func eachToggleFlipsVisibility() async {
            await propertyCheck(count: 50, input: Gen.bool, toggles) { initial, count in
                await Live.failOnThrow {
                    try withPanel(visible: initial) { panel in
                        try #require(
                            panel.isVisible == initial, "precondition: the panel must start with isVisible \(initial)")
                        (0..<count).forEach { _ in PanelVisibility.toggle(panel) }
                        let expected = initial == count.isMultiple(of: 2)
                        #expect(
                            panel.isVisible == expected,
                            "a panel starting with isVisible \(initial) must have isVisible \(expected) after \(count) toggles"
                        )
                    }
                }
            }
        }

        @Test func togglingKeepsFrame() async {
            await propertyCheck(count: 50, input: Gen.bool, toggles) { initial, count in
                withPanel(visible: initial) { panel in
                    let frame = panel.frame
                    (0..<count).forEach { _ in PanelVisibility.toggle(panel) }
                    #expect(
                        panel.frame == frame,
                        "after \(count) toggles from isVisible \(initial) the panel must stay at \(frame); got \(panel.frame)"
                    )
                }
            }
        }
    }
}
