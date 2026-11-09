import CoreGraphics
import Foundation
import WindowListCore

public enum FixtureError: Error, CustomStringConvertible {
    case binaryNotFound(String)
    case launchFailed(String)
    case timeout(command: String)
    case closed(command: String)
    case badReply(String)
    case commandFailed(String)

    public var description: String {
        switch self {
        case .binaryNotFound(let path):
            "AXFixture binary not found at \(path); it is built as a dependency of WindowListAXTests by `swift test`"
        case .launchFailed(let reason): "failed to launch AXFixture: \(reason)"
        case .timeout(let command): "AXFixture did not reply to \(command) in time"
        case .closed(let command): "AXFixture exited before replying to \(command)"
        case .badReply(let line): "AXFixture sent an undecodable reply: \(line)"
        case .commandFailed(let reason): "AXFixture command failed: \(reason)"
        }
    }
}

/// A running AXFixture process; terminate it (or let it deinit) to close all its windows.
public final class Fixture {
    public enum Style: String, Sendable {
        case titled, borderless
    }

    public static let replyTimeout: Duration = .seconds(10)

    public let process: ProcessID
    private let task: Process
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()

    public static var binaryURL: URL {
        Bundle(for: Fixture.self).bundleURL.deletingLastPathComponent().appending(path: "AXFixture")
    }

    /// `accessory` runs the fixture without a Dock icon, like the LSUIElement app.
    public init(accessory: Bool = false) throws(FixtureError) {
        let url = Self.binaryURL
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw .binaryNotFound(url.path) }
        let task = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        task.executableURL = url
        task.arguments = accessory ? ["--accessory"] : []
        task.standardInput = stdin
        task.standardOutput = stdout
        do {
            try task.run()
        } catch {
            throw .launchFailed(String(describing: error))
        }
        guard let process = ProcessID(task.processIdentifier) else {
            task.terminate()
            throw .launchFailed("invalid pid \(task.processIdentifier)")
        }
        self.task = task
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.output = stdout.fileHandleForReading
        _ = try send(["op": "ping"])
    }

    deinit { terminate() }

    public var isRunning: Bool { task.isRunning }

    public func open(title: String, width: Double = 420, height: Double = 280, style: Style = .titled)
        throws(FixtureError) -> WindowID
    {
        let reply = try send(["op": "open", "title": title, "width": width, "height": height, "style": style.rawValue])
        guard let raw = reply.wid, let number = CGWindowID(exactly: raw), let id = WindowID(number) else {
            throw .badReply("open returned no valid wid: \(String(describing: reply.wid))")
        }
        return id
    }

    public func openPanel(title: String) throws(FixtureError) -> WindowID {
        let reply = try send(["op": "openPanel", "title": title])
        guard let raw = reply.wid, let number = CGWindowID(exactly: raw), let id = WindowID(number) else {
            throw .badReply("openPanel returned no valid wid: \(String(describing: reply.wid))")
        }
        return id
    }

    public func minimize(_ id: WindowID) throws(FixtureError) {
        _ = try send(["op": "minimize", "wid": Int(id.rawValue)])
    }

    public func orderOut(_ id: WindowID) throws(FixtureError) {
        _ = try send(["op": "orderOut", "wid": Int(id.rawValue)])
    }

    public func setFullScreen(_ id: WindowID, _ fullScreen: Bool) throws(FixtureError) {
        _ = try send(["op": fullScreen ? "enterFullScreen" : "exitFullScreen", "wid": Int(id.rawValue)])
    }

    public func close(_ id: WindowID) throws(FixtureError) {
        _ = try send(["op": "close", "wid": Int(id.rawValue)])
    }

    public func terminate() {
        guard task.isRunning else { return }
        task.terminate()
        task.waitUntilExit()
    }

    private struct Reply: Decodable {
        let ok: Bool
        let wid: Int?
        let error: String?
    }

    private func send(_ command: [String: any Sendable]) throws(FixtureError) -> Reply {
        let name = String(describing: command["op"] ?? "?")
        guard var data = try? JSONSerialization.data(withJSONObject: command) else {
            throw .commandFailed("unencodable command \(command)")
        }
        data.append(UInt8(ascii: "\n"))
        do {
            try input.write(contentsOf: data)
        } catch {
            throw .closed(command: name)
        }
        let line = try readLine(command: name)
        guard let reply = try? JSONDecoder().decode(Reply.self, from: line) else {
            throw .badReply(String(decoding: line, as: UTF8.self))
        }
        guard reply.ok else { throw .commandFailed(reply.error ?? "\(name) failed without a reason") }
        return reply
    }

    private func readLine(command: String) throws(FixtureError) -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.replyTimeout)
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return Data(line)
            }
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { throw .timeout(command: command) }
            let milliseconds = Int32(clamping: remaining.components.seconds * 1000 + 1)
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, milliseconds)
            guard ready > 0 else { continue }
            let chunk = output.availableData
            guard !chunk.isEmpty else { throw .closed(command: command) }
            buffer.append(chunk)
        }
    }
}
