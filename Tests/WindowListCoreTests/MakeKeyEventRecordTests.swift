import CoreGraphics
import PropertyBased
import Testing
import WindowListCore

@Suite struct MakeKeyEventRecordTests {
    private static let specifiedRanges: [Range<Int>] = [
        0x04..<0x05, 0x08..<0x09, 0x20..<0x30, 0x3a..<0x3b, 0x3c..<0x40,
    ]

    @Test func lengthFieldIs0xF8() async {
        await propertyCheck(count: 500, input: Generators.windowID) { window in
            let byte = MakeKeyEventRecord(window: window).bytes[0x04]
            #expect(byte == 0xf8, "record length byte at 0x04 must be 0xf8, got \(byte)")
        }
    }

    @Test func eventTypeIsLeftMouseDown() async {
        await propertyCheck(count: 500, input: Generators.windowID) { window in
            let byte = MakeKeyEventRecord(window: window).bytes[0x08]
            #expect(
                byte == UInt8(CGEventType.leftMouseDown.rawValue),
                "event type at 0x08 must be leftMouseDown, got \(byte)")
        }
    }

    @Test func flagAt0x3AIs0x10() async {
        await propertyCheck(count: 500, input: Generators.windowID) { window in
            let byte = MakeKeyEventRecord(window: window).bytes[0x3a]
            #expect(byte == 0x10, "flag byte at 0x3a must be 0x10, got \(byte)")
        }
    }

    @Test func windowIDFieldMatchesNativeLayout() async {
        await propertyCheck(count: 500, input: Generators.windowID) { window in
            let actual = slice(MakeKeyEventRecord(window: window).bytes, 0x3c..<0x40)
            let expected = nativeBytes(of: window.rawValue)
            #expect(actual == expected, "wid bytes \(actual) must match memcpy layout of \(window): \(expected)")
        }
    }

    @Test func pointMatchesNativeCGPointLayout() async {
        await propertyCheck(count: 500, input: Generators.windowID) { window in
            let actual = slice(MakeKeyEventRecord(window: window).bytes, 0x20..<0x30)
            let expected = nativeBytes(of: MakeKeyEventRecord.offWindowPoint)
            #expect(actual == expected, "point bytes \(actual) must match memcpy layout of CGPoint \(expected)")
        }
    }

    @Test func pointIsOutsideAnyWindow() async {
        await propertyCheck(count: 500, input: Generators.windowID) { window in
            let point = MakeKeyEventRecord(window: window).windowLocation
            #expect(
                point.x > 100_000 && point.y > 100_000,
                "click point \(point) must be far past any window's bottom-right")
        }
    }

    @Test func unspecifiedBytesAreZero() async {
        await propertyCheck(count: 500, input: Generators.windowID) { window in
            let bytes = MakeKeyEventRecord(window: window).bytes
            let stray = bytes.indices.filter { index in
                !Self.specifiedRanges.contains { $0.contains(index) } && bytes[index] != 0
            }
            #expect(stray.isEmpty, "bytes outside documented fields must be zero; non-zero at \(stray)")
        }
    }
}
