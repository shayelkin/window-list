import PropertyBased
import Testing
import WindowListCore

@Suite struct RemoteTokenTests {
    @Test func pidFieldRoundTrips() async {
        await propertyCheck(count: 500, input: Generators.processID, Generators.elementID) { process, element in
            let token = RemoteToken(process: process, element: element)
            let pid = token.bytes.loadLittleEndian(Int32.self, at: RemoteToken.pidOffset)
            #expect(pid == process.rawValue, "pid field \(pid) must equal \(process)")
        }
    }

    @Test func pidFieldMatchesNativeLayout() async {
        await propertyCheck(count: 500, input: Generators.processID, Generators.elementID) { process, element in
            let token = RemoteToken(process: process, element: element)
            let actual = slice(token.bytes, 0..<4)
            let expected = nativeBytes(of: process.rawValue)
            #expect(actual == expected, "pid bytes \(actual) must match memcpy layout \(expected)")
        }
    }

    @Test func paddingIsZero() async {
        await propertyCheck(count: 500, input: Generators.processID, Generators.elementID) { process, element in
            let token = RemoteToken(process: process, element: element)
            let padding = slice(token.bytes, 4..<8)
            #expect(padding == [0, 0, 0, 0], "bytes 4..<8 must be zero, got \(padding)")
        }
    }

    @Test func magicIsCoco() async {
        await propertyCheck(count: 500, input: Generators.processID, Generators.elementID) { process, element in
            let token = RemoteToken(process: process, element: element)
            let magic = slice(token.bytes, 8..<12)
            #expect(magic == nativeBytes(of: UInt32(0x636f_636f)), "bytes 8..<12 must be 0x636f636f, got \(magic)")
        }
    }

    @Test func elementIDFieldMatchesNativeLayout() async {
        await propertyCheck(count: 500, input: Generators.processID, Generators.elementID) { process, element in
            let token = RemoteToken(process: process, element: element)
            let actual = slice(token.bytes, 12..<20)
            let expected = nativeBytes(of: element.rawValue)
            #expect(actual == expected, "element bytes \(actual) must match memcpy layout \(expected)")
        }
    }

    @Test func elementIDFieldRoundTrips() async {
        await propertyCheck(count: 500, input: Generators.processID, Generators.elementID) { process, element in
            let token = RemoteToken(process: process, element: element)
            let loaded = token.bytes.loadLittleEndian(UInt64.self, at: RemoteToken.elementOffset)
            #expect(loaded == element.rawValue, "element field \(loaded) must equal \(element)")
        }
    }
}
