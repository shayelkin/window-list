import PropertyBased
import Testing
import WindowListCore

@Suite struct IdentifiersTests {
    @Test func processIDRejectsNonPositive() async {
        await propertyCheck(count: 500, input: Gen.int32(in: Int32.min...0)) { raw in
            #expect(ProcessID(raw) == nil, "ProcessID must reject non-positive pid \(raw)")
        }
    }

    @Test func processIDRoundTripsPositive() async {
        await propertyCheck(count: 500, input: Gen.int32(in: 1...Int32.max)) { raw in
            #expect(ProcessID(raw)?.rawValue == raw, "ProcessID(\(raw)) must keep the raw pid")
        }
    }

    @Test func windowIDRejectsZero() {
        #expect(WindowID(0) == nil, "WindowID must reject 0 (kCGNullWindowID)")
    }

    @Test func windowIDRoundTripsNonZero() async {
        await propertyCheck(count: 500, input: Gen.uint32(in: 1...UInt32.max)) { raw in
            #expect(WindowID(raw)?.rawValue == raw, "WindowID(\(raw)) must keep the raw id")
        }
    }

    @Test func windowIDOrderMatchesRawOrder() async {
        await propertyCheck(count: 500, input: Generators.windowID, Generators.windowID) { lhs, rhs in
            #expect((lhs < rhs) == (lhs.rawValue < rhs.rawValue), "WindowID order must follow raw ids \(lhs), \(rhs)")
        }
    }

    @Test func elementIDSuccessorIncrements() async {
        await propertyCheck(count: 500, input: Gen.uint64(in: 0...(UInt64.max - 1))) { raw in
            #expect(AXElementID(raw).successor?.rawValue == raw + 1, "successor of \(raw) must be \(raw + 1)")
        }
    }

    @Test func elementIDSuccessorOfMaxIsNil() {
        #expect(AXElementID(.max).successor == nil, "successor of UInt64.max must be nil, not wrap to 0")
    }
}
