import AppKit
import PropertyBased
import Testing
import WindowListCore

private let contentHeight = Gen.int(in: 0...4000).map { CGFloat($0) }
private let fraction = Gen.double(in: 0...1)

extension LiveAXTests {
    /// Fits a real in-process panel styled like the app's, so the titlebar and visible-frame geometry come from AppKit.
    @MainActor @Suite struct PanelSizing {
        func withPanel(topAt fraction: Double, _ body: (NSPanel, CGRect) throws -> Void) throws {
            _ = NSApplication.shared
            let screen = try #require(NSScreen.main, "precondition: a main screen must exist to place the panel on")
            let visible = screen.visibleFrame
            let top = visible.maxY - (visible.height * fraction).rounded()
            let panel = NSPanel(
                contentRect: NSRect(x: visible.minX + 40, y: top - 240, width: 320, height: 240),
                styleMask: PanelStyle.styleMask,
                backing: .buffered,
                defer: false
            )
            PanelStyle.apply(to: panel)
            panel.isReleasedWhenClosed = false
            panel.setFrame(NSRect(x: visible.minX + 40, y: top - 240, width: 320, height: 240), display: false)
            defer { panel.close() }
            try body(panel, (panel.screen ?? screen).visibleFrame)
        }

        @Test func fittedPanelLiesWithinVisibleFrame() async {
            await propertyCheck(count: 100, input: contentHeight, fraction) { height, at in
                await Live.failOnThrow {
                    try withPanel(topAt: at) { panel, visible in
                        PanelFrame.fit(panel, contentHeight: height)
                        #expect(
                            panel.frame.minY >= visible.minY && panel.frame.maxY <= visible.maxY,
                            "panel fitted to \(height) at \(panel.frame) must lie within visible frame \(visible)"
                        )
                    }
                }
            }
        }

        @Test func fittedContentAreaMatchesListUntilScreenIsFull() async {
            await propertyCheck(count: 100, input: contentHeight, fraction) { height, at in
                await Live.failOnThrow {
                    try withPanel(topAt: at) { panel, visible in
                        let titlebar = panel.frame.height - panel.contentLayoutRect.height
                        PanelFrame.fit(panel, contentHeight: height)
                        let expected = min(height, visible.height - titlebar)
                        #expect(
                            panel.contentLayoutRect.height == expected,
                            """
                            content area below the \(titlebar) titlebar must be \(expected) for content \(height) \
                            on a \(visible.height) visible frame; got \(panel.contentLayoutRect.height)
                            """
                        )
                    }
                }
            }
        }

        @Test func fittedPanelHeightIsLocked() async {
            await propertyCheck(count: 100, input: contentHeight, fraction) { height, at in
                await Live.failOnThrow {
                    try withPanel(topAt: at) { panel, _ in
                        PanelFrame.fit(panel, contentHeight: height)
                        #expect(
                            panel.minSize.height == panel.frame.height && panel.maxSize.height == panel.frame.height,
                            """
                            min/max height \(panel.minSize.height)/\(panel.maxSize.height) must both equal the \
                            fitted height \(panel.frame.height) so the user can only resize the width
                            """
                        )
                    }
                }
            }
        }
    }
}
