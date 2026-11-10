import CoreGraphics
import PropertyBased
import Testing
import WindowListCore

private let coordinate = Gen.int(in: -5000...5000).map { CGFloat($0) }
private let length = Gen.int(in: 1...3000).map { CGFloat($0) }
private let rect = zip(coordinate, coordinate, length, length).map { CGRect(x: $0, y: $1, width: $2, height: $3) }
/// Includes negative and far-too-tall requests.
private let height = Gen.int(in: -100...7000).map { CGFloat($0) }
private let fraction = Gen.double(in: 0...1)

/// A frame whose top edge lies within `visible`, `fraction` of the way down from its top.
private func frame(below visible: CGRect, at fraction: Double, from base: CGRect) -> CGRect {
    let top = visible.maxY - (visible.height * fraction).rounded()
    return CGRect(x: base.minX, y: top - base.height, width: base.width, height: base.height)
}

@Suite struct PanelFrameTests {
    @Test func heightIsRequestClampedToVisibleHeight() async {
        await propertyCheck(count: 1000, input: rect, height, rect) { frame, height, visible in
            let result = PanelFrame.fitting(frame, height: height, in: visible)
            let expected = min(max(height, 0), visible.height)
            #expect(
                result.height == expected, "height \(result.height) must be \(height) clamped to 0…\(visible.height)")
        }
    }

    @Test func resultLiesVerticallyWithinVisible() async {
        await propertyCheck(count: 1000, input: rect, height, rect) { frame, height, visible in
            let result = PanelFrame.fitting(frame, height: height, in: visible)
            #expect(
                result.minY >= visible.minY && result.maxY <= visible.maxY,
                "\(result) fitted from \(frame) must lie within \(visible.minY)…\(visible.maxY)"
            )
        }
    }

    @Test func horizontalGeometryIsUnchanged() async {
        await propertyCheck(count: 1000, input: rect, height, rect) { frame, height, visible in
            let result = PanelFrame.fitting(frame, height: height, in: visible)
            #expect(
                result.minX == frame.minX && result.width == frame.width,
                "\(result) must keep the x \(frame.minX) and width \(frame.width) of \(frame)"
            )
        }
    }

    @Test func keepsTopEdgeWhileThereIsRoomBelow() async {
        await propertyCheck(count: 1000, input: rect, fraction, rect, fraction) { base, at, visible, share in
            let frame = frame(below: visible, at: at, from: base)
            let room = frame.maxY - visible.minY
            let height = (room * share).rounded()
            let result = PanelFrame.fitting(frame, height: height, in: visible)
            #expect(
                result.maxY == frame.maxY,
                "fitting \(frame) to \(height) with \(room) of room below must keep its top; got \(result)"
            )
        }
    }

    @Test func growsUpFromVisibleBottomOnceOutOfRoomBelow() async {
        await propertyCheck(count: 1000, input: rect, fraction, rect, height) { base, at, visible, height in
            let frame = frame(below: visible, at: at, from: base)
            let room = frame.maxY - visible.minY
            let result = PanelFrame.fitting(frame, height: height, in: visible)
            guard height > room else { return }
            #expect(
                result.minY == visible.minY,
                "fitting \(frame) to \(height) with only \(room) below must sit on \(visible.minY); got \(result)"
            )
        }
    }

    @Test func fillsVisibleHeightWhenRequestExceedsIt() async {
        await propertyCheck(count: 1000, input: rect, height, rect) { frame, height, visible in
            let result = PanelFrame.fitting(frame, height: height, in: visible)
            guard height >= visible.height else { return }
            #expect(
                result.minY == visible.minY && result.maxY == visible.maxY,
                "request \(height) ≥ visible \(visible.height) must span \(visible.minY)…\(visible.maxY); got \(result)"
            )
        }
    }

    @Test func refittingIsStable() async {
        await propertyCheck(count: 1000, input: rect, height, rect) { frame, height, visible in
            let once = PanelFrame.fitting(frame, height: height, in: visible)
            let twice = PanelFrame.fitting(once, height: height, in: visible)
            #expect(twice == once, "refitting \(once) to the same height must not move it; got \(twice)")
        }
    }
}
