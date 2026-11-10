import AppKit
import Carbon.HIToolbox
import PropertyBased
import Testing
import WindowListCore

private let keyCode = Gen.int(in: 0...127).map { CGKeyCode($0) }
private let supported: [NSEvent.ModifierFlags] = [.command, .control, .option, .shift]
private let unsupported: [NSEvent.ModifierFlags] = [.capsLock, .function, .numericPad, .help]

/// The members of `list` whose bit is set in `mask`.
private func flags(_ mask: Int, of list: [NSEvent.ModifierFlags]) -> NSEvent.ModifierFlags {
    list.enumerated().filter { mask & (1 << $0.offset) != 0 }.reduce(NSEvent.ModifierFlags()) { $0.union($1.element) }
}

/// Supported modifiers including at least one of Command and Control.
private let valid = Gen.int(in: 0..<16).map { flags($0, of: supported) }
    .filter { !$0.isDisjoint(with: [.command, .control]) }
private let optionShiftOnly = Gen.int(in: 0..<4).map { flags($0, of: [.option, .shift]) }
/// Valid modifiers plus at least one unsupported one.
private let withUnsupported = zip(valid, Gen.int(in: 1..<16)).map { $0.union(flags($1, of: unsupported)) }

@Suite struct HotKeyCombinationTests {
    @Test func validCombinationKeepsKeyAndModifiers() async {
        await propertyCheck(input: keyCode, valid) { key, modifiers in
            let combination = try? HotKeyCombination(keyCode: key, modifiers: modifiers)
            #expect(
                combination?.keyCode == key && combination?.modifiers == modifiers,
                "keyCode \(key) with modifiers 0x\(String(modifiers.rawValue, radix: 16)) must be accepted as is"
            )
        }
    }

    @Test func optionShiftOnlyIsRejected() async {
        await propertyCheck(input: keyCode, optionShiftOnly) { key, modifiers in
            #expect(
                throws: HotKeyError.needsCommandOrControl,
                "modifiers 0x\(String(modifiers.rawValue, radix: 16)) lack Command and Control, which macOS requires"
            ) { try HotKeyCombination(keyCode: key, modifiers: modifiers) }
        }
    }

    @Test func unsupportedModifiersAreRejected() async {
        await propertyCheck(input: keyCode, withUnsupported) { key, modifiers in
            let extra = modifiers.subtracting(HotKeyCombination.supportedModifiers).rawValue
            #expect(
                throws: HotKeyError.unsupportedModifiers(extra),
                "modifiers 0x\(String(modifiers.rawValue, radix: 16)) must be rejected for 0x\(String(extra, radix: 16))"
            ) { try HotKeyCombination(keyCode: key, modifiers: modifiers) }
        }
    }

    @Test func carbonModifiersMirrorModifiers() async {
        let pairs: [(NSEvent.ModifierFlags, Int)] = [
            (.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey),
        ]
        await propertyCheck(input: keyCode, valid) { key, modifiers in
            let mask = try? HotKeyCombination(keyCode: key, modifiers: modifiers).carbonModifiers
            let expected = pairs.filter { modifiers.contains($0.0) }.reduce(UInt32(0)) { $0 | UInt32($1.1) }
            #expect(
                mask == expected,
                "Carbon mask for 0x\(String(modifiers.rawValue, radix: 16)) must be \(expected); got \(String(describing: mask))"
            )
        }
    }

    @Test func eventFlagsMirrorModifiers() async {
        let pairs: [(NSEvent.ModifierFlags, CGEventFlags)] = [
            (.command, .maskCommand), (.control, .maskControl), (.option, .maskAlternate), (.shift, .maskShift),
        ]
        await propertyCheck(input: keyCode, valid) { key, modifiers in
            let flags = try? HotKeyCombination(keyCode: key, modifiers: modifiers).eventFlags
            let expected = pairs.filter { modifiers.contains($0.0) }.reduce(CGEventFlags()) { $0.union($1.1) }
            #expect(
                flags == expected,
                "event flags for 0x\(String(modifiers.rawValue, radix: 16)) must be \(expected); got \(String(describing: flags))"
            )
        }
    }

    @Test func toggleListIsControlCommandB() {
        #expect(
            HotKeyCombination.toggleList.keyCode == CGKeyCode(kVK_ANSI_B)
                && HotKeyCombination.toggleList.modifiers == [.command, .control],
            "the list shortcut must be ⌃⌘B; got \(HotKeyCombination.toggleList)"
        )
    }
}
