import CoreGraphics
import PropertyBased
import WindowListCore

enum Generators {
    static let processID = Gen.int32(in: 1...Int32.max).compactMap { ProcessID($0) }
    static let windowID = Gen.uint32(in: 1...UInt32.max).compactMap { WindowID($0) }
    static let elementID = Gen.uint64().map { AXElementID($0) }

    /// Mixed-case ASCII, Greek, Japanese and accented characters, including the empty string.
    static let text = Gen<Character>.oneOf(
        Gen.character(in: "a"..."z"),
        Gen.character(in: "A"..."Z"),
        Gen.character(in: "α"..."ω"),
        Gen.character(in: "あ"..."ん"),
        Gen.character(in: "À"..."ÿ")
    ).string(of: 0...6)
}

/// Deterministic shuffling driven by a generated seed (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Bytes `memcpy` would produce for `value` — the layout the private APIs read.
func nativeBytes<T>(of value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}

func slice<let count: Int>(_ bytes: InlineArray<count, UInt8>, _ range: Range<Int>) -> [UInt8] {
    range.map { bytes[$0] }
}
