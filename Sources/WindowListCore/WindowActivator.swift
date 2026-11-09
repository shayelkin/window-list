import AppKit
import ApplicationServices

public enum ActivationError: Error, Equatable, Sendable {
    case unminimizeFailed(AXFailure)
    case processNotFound(ProcessID)
    case frontProcessFailed(CGError)
    case makeKeyFailed(CGError)
    case elementUnavailable(WindowID)
    case raiseFailed(AXFailure)
}

public enum WindowActivator {
    /// How long an unseen window may take to surface as its app's focused window after being made key.
    public static let focusTimeout: Duration = .seconds(1)

    /// Focuses `entry`'s window, switching Space if needed.
    /// Sequence adapted from AltTab's window focusing (front process + make-key event + AXRaise):
    /// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/SkyLight.framework.swift
    /// The front process + make-key steps only need the window id, which is what makes unseen windows reachable:
    /// once key, the app vends the window as `kAXFocusedWindow`, and `AXRaise` on it switches to its Space.
    public static func activate(_ entry: WindowEntry) async throws(ActivationError) {
        if case .resolved(let window) = entry.access, entry.isMinimized {
            do throws(AXFailure) {
                try window.element.set(kAXMinimizedAttribute, to: false)
            } catch {
                throw .unminimizeFailed(error)
            }
        }
        guard var psn = PrivateAPI.processSerialNumber(for: entry.process) else {
            throw .processNotFound(entry.process)
        }
        let front = PrivateAPI.setFrontProcess(&psn, window: entry.id)
        guard front == .success else { throw .frontProcessFailed(front) }
        let key = PrivateAPI.postMakeKey(&psn, record: MakeKeyEventRecord(window: entry.id))
        guard key == .success else { throw .makeKeyFailed(key) }
        let window: AXWindow
        switch entry.access {
        case .resolved(let known):
            window = known
        case .unresolved:
            guard let focused = await focusedWindow(of: entry.process, matching: entry.id) else {
                throw .elementUnavailable(entry.id)
            }
            window = focused
        }
        do throws(AXFailure) {
            try window.element.perform(kAXRaiseAction)
        } catch {
            throw .raiseFailed(error)
        }
    }

    /// Public-API fallback: activates the app, then raises the window when its element is known.
    public static func activateFallback(_ entry: WindowEntry) {
        NSRunningApplication(processIdentifier: entry.process.rawValue)?.activate()
        guard case .resolved(let window) = entry.access else { return }
        try? window.element.perform(kAXRaiseAction)
    }

    private static func focusedWindow(of process: ProcessID, matching id: WindowID) async -> AXWindow? {
        let app = AXApplication(process: process)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: focusTimeout)
        while clock.now < deadline {
            if let element = try? app.element.element(kAXFocusedWindowAttribute),
                let window = AXWindow(validating: element, expected: id)
            {
                return window
            }
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return nil
            }
        }
        return nil
    }
}
