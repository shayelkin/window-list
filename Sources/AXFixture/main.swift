// Test-only GUI helper driven over stdin/stdout with one JSON object per line.
import AppKit
import WindowListCore

struct Command: Decodable {
    enum Op: String, Decodable {
        case ping, open, openPanel, minimize, orderOut, enterFullScreen, exitFullScreen, close, quit
    }
    enum Style: String, Decodable {
        case titled, borderless
    }

    let op: Op
    let title: String?
    let width: Double?
    let height: Double?
    let style: Style?
    let wid: Int?
}

struct Reply: Encodable {
    let ok: Bool
    let wid: Int?
    let error: String?

    static func success(wid: Int? = nil) -> Reply { Reply(ok: true, wid: wid, error: nil) }
    static func failure(_ error: String) -> Reply { Reply(ok: false, wid: nil, error: error) }
}

@MainActor
final class Flag {
    var isSet = false
}

@MainActor
final class FixtureController {
    private var windows: [Int: NSWindow] = [:]

    func handle(_ line: String) {
        guard let data = line.data(using: .utf8), let command = try? JSONDecoder().decode(Command.self, from: data)
        else {
            send(.failure("undecodable command: \(line)"))
            return
        }
        switch command.op {
        case .ping: send(.success())
        case .open: send(open(command))
        case .openPanel: send(openPanel(command))
        case .minimize: minimize(command)
        case .orderOut: send(orderOut(command))
        case .enterFullScreen: setFullScreen(command, true)
        case .exitFullScreen: setFullScreen(command, false)
        case .close: send(close(command))
        case .quit:
            send(.success())
            NSApp.terminate(nil)
        }
    }

    private func open(_ command: Command) -> Reply {
        guard let width = command.width, let height = command.height, width > 0, height > 0 else {
            return .failure("open requires positive width and height")
        }
        let style: NSWindow.StyleMask =
            switch command.style ?? .titled {
            case .titled: [.titled, .closable, .miniaturizable, .resizable]
            case .borderless: [.borderless]
            }
        let offset = Double(windows.count % 10) * 24
        let window = NSWindow(
            contentRect: NSRect(x: 120 + offset, y: 120 + offset, width: width, height: height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = command.title ?? ""
        window.orderFrontRegardless()
        let wid = window.windowNumber
        guard wid > 0 else { return .failure("window has no window number after ordering front") }
        windows[wid] = window
        return .success(wid: wid)
    }

    /// A panel configured exactly like the app's list panel.
    private func openPanel(_ command: Command) -> Reply {
        let panel = NSPanel(
            contentRect: NSRect(x: 160, y: 160, width: 320, height: 240),
            styleMask: PanelStyle.styleMask,
            backing: .buffered,
            defer: false
        )
        PanelStyle.apply(to: panel)
        panel.isReleasedWhenClosed = false
        panel.title = command.title ?? ""
        panel.orderFrontRegardless()
        let wid = panel.windowNumber
        guard wid > 0 else { return .failure("panel has no window number after ordering front") }
        windows[wid] = panel
        return .success(wid: wid)
    }

    private func minimize(_ command: Command) {
        guard let wid = command.wid, let window = windows[wid] else {
            send(.failure("unknown wid \(String(describing: command.wid))"))
            return
        }
        window.miniaturize(nil)
        waitUntil(deadline: .now + .seconds(5), { window.isMiniaturized }) { [weak self] done in
            self?.send(done ? .success(wid: wid) : .failure("window \(wid) did not miniaturize within 5 s"))
        }
    }

    private func orderOut(_ command: Command) -> Reply {
        guard let wid = command.wid, let window = windows[wid] else {
            return .failure("unknown wid \(String(describing: command.wid))")
        }
        window.orderOut(nil)
        return .success(wid: wid)
    }

    private func setFullScreen(_ command: Command, _ fullScreen: Bool) {
        guard let wid = command.wid, let window = windows[wid] else {
            send(.failure("unknown wid \(String(describing: command.wid))"))
            return
        }
        guard window.styleMask.contains(.fullScreen) != fullScreen else { return send(.success(wid: wid)) }
        // `.fullScreen` joins the style mask when the transition starts; reply only once it has finished, so the
        // caller never toggles mid-animation (AppKit ignores that).
        let name = fullScreen ? NSWindow.didEnterFullScreenNotification : NSWindow.didExitFullScreenNotification
        let finished = Flag()
        let observer = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { finished.isSet = true }
        }
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.toggleFullScreen(nil)
        waitUntil(deadline: .now + .seconds(5), { finished.isSet }) { [weak self] done in
            NotificationCenter.default.removeObserver(observer)
            let state = fullScreen ? "enter" : "exit"
            self?.send(done ? .success(wid: wid) : .failure("window \(wid) did not \(state) full screen within 5 s"))
        }
    }

    private func close(_ command: Command) -> Reply {
        guard let wid = command.wid, let window = windows.removeValue(forKey: wid) else {
            return .failure("unknown wid \(String(describing: command.wid))")
        }
        window.close()
        return .success(wid: wid)
    }

    private func waitUntil(
        deadline: ContinuousClock.Instant, _ condition: @escaping () -> Bool, then: @escaping (Bool) -> Void
    ) {
        guard !condition() else { return then(true) }
        guard ContinuousClock.now < deadline else { return then(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.waitUntil(deadline: deadline, condition, then: then) }
        }
    }

    private func send(_ reply: Reply) {
        guard var data = try? JSONEncoder().encode(reply) else { return }
        data.append(UInt8(ascii: "\n"))
        FileHandle.standardOutput.write(data)
    }
}

let controller = FixtureController()
let app = NSApplication.shared
app.setActivationPolicy(CommandLine.arguments.contains("--accessory") ? .accessory : .regular)

Thread.detachNewThread {
    while let line = readLine() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { controller.handle(line) }
        }
    }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { NSApp.terminate(nil) }
    }
}

app.run()
