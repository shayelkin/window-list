import AXTestSupport
import CoreGraphics
import PropertyBased
import Testing

private struct Binding: Sendable, CustomStringConvertible {
    let ascii: Int
    let keyCode: Int
    let mask: UInt64

    var parameters: [Int] { [ascii, keyCode, Int(mask)] }

    func entry(enabled: Bool = true, type: String = "standard", parameters: [Any]? = nil) -> [String: Any] {
        ["enabled": enabled, "value": ["type": type, "parameters": parameters ?? self.parameters]]
    }

    var description: String { "(\(ascii), \(keyCode), 0x\(String(mask, radix: 16)))" }
}

private let supported = SymbolicHotKey.supportedModifiers.rawValue

private let binding = zip(
    Gen<Int>.oneOf(Gen.always(65535), Gen.int(in: 0...127)),
    Gen.int(in: 0...SymbolicHotKey.maximumKeyCode),
    Gen.uint64().map { $0 & supported }
).map { Binding(ascii: $0, keyCode: $1, mask: $2) }

private enum EntryPath: CaseIterable, Sendable {
    case enabled, value, type, parameters

    var label: String {
        switch self {
        case .enabled: "enabled"
        case .value: "value"
        case .type: "value.type"
        case .parameters: "value.parameters"
        }
    }

    func remove(from entry: [String: Any]) -> [String: Any] {
        replace(in: entry, with: nil)
    }

    func replace(in entry: [String: Any], with newValue: Any?) -> [String: Any] {
        var entry = entry
        switch self {
        case .enabled: entry["enabled"] = newValue
        case .value: entry["value"] = newValue
        case .type, .parameters:
            var value = entry["value"] as? [String: Any] ?? [:]
            value[self == .type ? "type" : "parameters"] = newValue
            entry["value"] = value
        }
        return entry
    }
}

private func failure(_ result: Result<SymbolicHotKey, HotKeyParseError>) -> HotKeyParseError? {
    guard case .failure(let error) = result else { return nil }
    return error
}

@Suite struct SymbolicHotKeyTests {
    @Test func parsesEveryWellFormedEntry() async {
        await propertyCheck(count: 500, input: binding) { binding in
            let result = SymbolicHotKey.parse(binding.entry())
            guard case .success(let hotKey) = result else {
                Issue.record("well-formed entry \(binding) must parse, got \(result)")
                return
            }
            #expect(
                Int(hotKey.keyCode) == binding.keyCode && hotKey.flags.rawValue == binding.mask,
                "parsed \(hotKey) must round-trip \(binding)"
            )
        }
    }

    @Test func rejectsMissingEntry() {
        #expect(failure(SymbolicHotKey.parse(nil)) == .missing, "an absent hotkey entry must be reported as missing")
    }

    @Test func rejectsDisabledEntry() async {
        await propertyCheck(count: 500, input: binding) { binding in
            let error = failure(SymbolicHotKey.parse(binding.entry(enabled: false)))
            #expect(
                error == .disabled,
                "disabled entry \(binding) must be rejected as disabled, got \(String(describing: error))")
        }
    }

    @Test func rejectsMissingKeys() async {
        await propertyCheck(count: 500, input: binding, Gen<EntryPath>.case) { binding, path in
            let error = failure(SymbolicHotKey.parse(path.remove(from: binding.entry())))
            #expect(
                error == .wrongType(path.label),
                "entry without \(path.label) must fail at that path, got \(String(describing: error))")
        }
    }

    @Test func rejectsMistypedValues() async {
        let wrong = Gen.character(in: "a"..."z").string(of: 0...5)
        await propertyCheck(count: 500, input: binding, Gen<EntryPath>.case, wrong) { binding, path, wrong in
            let replacement: Any = path == .type ? [wrong] : wrong
            let error = failure(SymbolicHotKey.parse(path.replace(in: binding.entry(), with: replacement)))
            #expect(
                error == .wrongType(path.label),
                "\(path.label) = \(replacement) must fail as wrong type, got \(String(describing: error))")
        }
    }

    @Test func rejectsNonDictionaryEntry() async {
        await propertyCheck(count: 500, input: binding) { binding in
            let error = failure(SymbolicHotKey.parse(binding.parameters))
            #expect(
                error == .wrongType("entry"),
                "a non-dictionary entry must fail as wrong type, got \(String(describing: error))")
        }
    }

    @Test func rejectsNonIntegerParameter() async {
        await propertyCheck(count: 500, input: binding, Gen.int(in: 0...2)) { binding, index in
            var parameters: [Any] = binding.parameters
            parameters[index] = "x"
            let error = failure(SymbolicHotKey.parse(binding.entry(parameters: parameters)))
            #expect(
                error == .wrongType("value.parameters[]"),
                "non-integer parameter \(index) must fail, got \(String(describing: error))")
        }
    }

    @Test func rejectsWrongParameterCount() async {
        let count = Gen<Int>.oneOf(Gen.int(in: 0...2), Gen.int(in: 4...8))
        await propertyCheck(count: 500, input: binding, count) { binding, count in
            let parameters = Array(repeating: binding.keyCode, count: count)
            let error = failure(SymbolicHotKey.parse(binding.entry(parameters: parameters)))
            #expect(
                error == .badParameterCount(count),
                "\(count) parameters must be rejected, got \(String(describing: error))")
        }
    }

    @Test func rejectsOutOfRangeKeyCode() async {
        let keyCode = Gen<Int>.oneOf(
            Gen.int(in: Int.min...(-1)), Gen.int(in: (SymbolicHotKey.maximumKeyCode + 1)...Int.max))
        await propertyCheck(count: 500, input: binding, keyCode) { binding, keyCode in
            let parameters = [binding.ascii, keyCode, Int(binding.mask)]
            let error = failure(SymbolicHotKey.parse(binding.entry(parameters: parameters)))
            #expect(
                error == .keyCodeOutOfRange(keyCode),
                "key code \(keyCode) must be rejected, got \(String(describing: error))")
        }
    }

    @Test func rejectsUnknownModifierBits() async {
        let unknown = Gen.uint64(in: 1...UInt64(Int.max)).map { $0 & ~supported & UInt64(Int.max) }.filter { $0 != 0 }
        await propertyCheck(count: 500, input: binding, unknown) { binding, unknown in
            let parameters = [binding.ascii, binding.keyCode, Int(binding.mask | unknown)]
            let error = failure(SymbolicHotKey.parse(binding.entry(parameters: parameters)))
            #expect(
                error == .unknownModifierBits(unknown),
                "unknown modifier bits 0x\(String(unknown, radix: 16)) must be rejected, got \(String(describing: error))"
            )
        }
    }

    @Test func rejectsNegativeModifierMask() async {
        await propertyCheck(count: 500, input: binding, Gen.int(in: Int.min...(-1))) { binding, mask in
            let parameters = [binding.ascii, binding.keyCode, mask]
            let error = failure(SymbolicHotKey.parse(binding.entry(parameters: parameters)))
            #expect(
                error == .wrongType("value.parameters[2]"),
                "negative mask \(mask) must be rejected, got \(String(describing: error))")
        }
    }

    @Test func rejectsNonStandardType() async {
        let type = Gen<Character>.oneOf(Gen.character(in: "a"..."z"), Gen.character(in: "A"..."Z"))
            .string(of: 0...10).filter { $0 != "standard" }
        await propertyCheck(count: 500, input: binding, type) { binding, type in
            let error = failure(SymbolicHotKey.parse(binding.entry(type: type)))
            #expect(
                error == .unsupportedType(type), "type \"\(type)\" must be rejected, got \(String(describing: error))")
        }
    }
}
