import CoreGraphics
import Foundation
import PropertyBased
import Testing
import WindowListCore

private let own = ProcessID.current

/// Fields of a window entry that `CGWindowInfo` must accept.
private struct ValidFields: Sendable, CustomStringConvertible {
    let number: Int
    let pid: Int32
    let alpha: Double
    let rect: CGRect

    var dictionary: [String: Any] {
        [
            kCGWindowNumber as String: number,
            kCGWindowOwnerPID as String: Int(pid),
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: rect.dictionaryRepresentation as NSDictionary as! [String: Any],
        ]
    }

    var description: String { "number \(number) pid \(pid) alpha \(alpha) rect \(rect)" }
}

private enum Key: CaseIterable, Sendable {
    case number, pid, layer, alpha, bounds

    var name: String {
        switch self {
        case .number: kCGWindowNumber as String
        case .pid: kCGWindowOwnerPID as String
        case .layer: kCGWindowLayer as String
        case .alpha: kCGWindowAlpha as String
        case .bounds: kCGWindowBounds as String
        }
    }
}

private enum WrongValue: CaseIterable, Sendable {
    case string, array, nested, null

    var value: Any {
        switch self {
        case .string: "42"
        case .array: [1, 2, 3]
        case .nested: ["X": "a"]
        case .null: NSNull()
        }
    }
}

private let validFields = zip(
    Gen.int(in: 1...Int(UInt32.max)),
    Gen.int32(in: 1...Int32.max).filter { $0 != own.rawValue },
    Gen.double(in: 0.001...1),
    zip(
        Gen.double(in: -10_000...10_000),
        Gen.double(in: -10_000...10_000),
        Gen.double(in: 50...5_000),
        Gen.double(in: 50...5_000)
    ).map { CGRect(x: $0, y: $1, width: $2, height: $3) }
).map { ValidFields(number: $0, pid: $1, alpha: $2, rect: $3) }

private func parse(_ dictionary: [String: Any]) -> CGWindowInfo? {
    CGWindowInfo(dictionary: dictionary, excluding: own)
}

@Suite struct CGWindowInfoTests {
    @Test func acceptsEveryValidDictionary() async {
        await propertyCheck(count: 500, input: validFields) { fields in
            #expect(parse(fields.dictionary) != nil, "valid window entry must parse: \(fields)")
        }
    }

    @Test func parsedFieldsMatchDictionary() async throws {
        await propertyCheck(count: 500, input: validFields) { fields in
            let info = try #require(parse(fields.dictionary), "valid window entry must parse: \(fields)")
            #expect(
                Int(info.id.rawValue) == fields.number && info.process.rawValue == fields.pid
                    && info.bounds.rect == fields.rect,
                "parsed \(info) must carry the dictionary's id, pid and bounds: \(fields)"
            )
        }
    }

    @Test func toleratesExtraKeys() async {
        await propertyCheck(count: 500, input: validFields, Generators.text) { fields, extra in
            var dictionary = fields.dictionary
            dictionary["extra-\(extra)"] = extra
            #expect(parse(dictionary) != nil, "unknown key \"extra-\(extra)\" must not reject \(fields)")
        }
    }

    @Test func rejectsNonZeroLayer() async {
        let layer = Gen.int(in: -1_000...1_000).filter { $0 != 0 }
        await propertyCheck(count: 500, input: validFields, layer) { fields, layer in
            var dictionary = fields.dictionary
            dictionary[kCGWindowLayer as String] = layer
            #expect(parse(dictionary) == nil, "layer \(layer) must be rejected: \(fields)")
        }
    }

    @Test func rejectsOwnProcess() async {
        await propertyCheck(count: 500, input: validFields) { fields in
            var dictionary = fields.dictionary
            dictionary[kCGWindowOwnerPID as String] = Int(own.rawValue)
            #expect(parse(dictionary) == nil, "own process \(own) must be rejected: \(fields)")
        }
    }

    @Test func rejectsInvalidPID() async {
        let pid = Gen<Int>.oneOf(Gen.int(in: Int(Int32.min)...0), Gen.int(in: (Int(Int32.max) + 1)...Int.max))
        await propertyCheck(count: 500, input: validFields, pid) { fields, pid in
            var dictionary = fields.dictionary
            dictionary[kCGWindowOwnerPID as String] = pid
            #expect(parse(dictionary) == nil, "pid \(pid) outside 1...Int32.max must be rejected")
        }
    }

    @Test func rejectsInvalidWindowNumber() async {
        let number = Gen<Int>.oneOf(Gen.int(in: Int.min...0), Gen.int(in: (Int(UInt32.max) + 1)...Int.max))
        await propertyCheck(count: 500, input: validFields, number) { fields, number in
            var dictionary = fields.dictionary
            dictionary[kCGWindowNumber as String] = number
            #expect(parse(dictionary) == nil, "window number \(number) outside 1...UInt32.max must be rejected")
        }
    }

    @Test func rejectsNonFiniteBounds() async {
        let bad = Gen.element(of: [Double.nan, .infinity, -.infinity]).compactMap { $0 }
        let component = Gen.int(in: 0...3)
        await propertyCheck(count: 500, input: validFields, bad, component) { fields, bad, component in
            var values = [fields.rect.origin.x, fields.rect.origin.y, fields.rect.width, fields.rect.height]
            values[component] = bad
            var dictionary = fields.dictionary
            dictionary[kCGWindowBounds as String] = [
                "X": values[0], "Y": values[1], "Width": values[2], "Height": values[3],
            ]
            #expect(parse(dictionary) == nil, "bounds component \(component) = \(bad) must be rejected")
        }
    }

    @Test func rejectsUndersizedBounds() async {
        let small = Gen.double(in: 0..<50)
        await propertyCheck(count: 500, input: validFields, small, Gen.bool) { fields, small, shrinkWidth in
            var rect = fields.rect
            if shrinkWidth { rect.size.width = small } else { rect.size.height = small }
            var dictionary = fields.dictionary
            dictionary[kCGWindowBounds as String] = rect.dictionaryRepresentation as NSDictionary as! [String: Any]
            #expect(parse(dictionary) == nil, "bounds \(rect) smaller than 50pt must be rejected")
        }
    }

    @Test func rejectsNonPositiveAlpha() async {
        let alpha = Gen<Double>.oneOf(Gen.double(in: -1...0), Gen.always(.nan))
        await propertyCheck(count: 500, input: validFields, alpha) { fields, alpha in
            var dictionary = fields.dictionary
            dictionary[kCGWindowAlpha as String] = alpha
            #expect(parse(dictionary) == nil, "alpha \(alpha) must be rejected")
        }
    }

    @Test func rejectsMissingKey() async {
        await propertyCheck(count: 500, input: validFields, Gen<Key>.case) { fields, key in
            var dictionary = fields.dictionary
            dictionary[key.name] = nil
            #expect(parse(dictionary) == nil, "entry without \(key.name) must be rejected")
        }
    }

    @Test func rejectsMistypedValue() async {
        await propertyCheck(count: 500, input: validFields, Gen<Key>.case, Gen<WrongValue>.case) { fields, key, wrong in
            var dictionary = fields.dictionary
            dictionary[key.name] = wrong.value
            #expect(parse(dictionary) == nil, "\(key.name) = \(wrong.value) (wrong type) must be rejected")
        }
    }
}

extension CGWindowInfoTests {
    @Test func rejectsFractionalIntegerField() async {
        let key = Gen.element(of: [Key.number, .pid, .layer]).compactMap { $0 }
        await propertyCheck(count: 500, input: validFields, key, Gen.int(in: 0...1_000_000)) { fields, key, whole in
            var dictionary = fields.dictionary
            let fraction = Double(whole) + 0.5
            dictionary[key.name] = fraction
            #expect(parse(dictionary) == nil, "\(key.name) = \(fraction) (non-integer) must be rejected")
        }
    }
}
