import AppKit
import Observation

@MainActor
@Observable
public final class WindowListModel {
    public static let refreshInterval: Duration = .seconds(3)
    public static let permissionPollInterval: Duration = .seconds(1)

    public private(set) var entries: [WindowEntry] = []
    public private(set) var highlight = Highlight()
    public private(set) var isTrusted = AccessibilityPermission.isTrusted

    @ObservationIgnored private let enumerator = WindowEnumerator()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var icons: [ProcessID: NSImage] = [:]
    @ObservationIgnored private lazy var creationObserver = WindowCreationObserver { [weak self] _, _ in
        self?.refresh()
    }

    public init() {}

    public func start() {
        guard loopTask == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        loopTask = Task { [weak self] in
            while let self {
                self.tick()
                let interval = self.isTrusted ? Self.refreshInterval : Self.permissionPollInterval
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        creationObserver.stop()
    }

    public func requestPermission() {
        AccessibilityPermission.request()
    }

    /// Coalesced: at most one snapshot runs at a time, and requests made meanwhile collapse into one follow-up.
    public func refresh() {
        guard isTrusted else { return }
        guard refreshTask == nil else {
            refreshRequested = true
            return
        }
        refreshTask = Task { [weak self] in
            await self?.runRefreshes()
        }
    }

    public func highlight(_ id: WindowID?) {
        highlight.set(id)
    }

    public func activate(_ id: WindowID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        Task { [weak self] in
            do throws(ActivationError) {
                try await WindowActivator.activate(entry)
            } catch {
                WindowActivator.activateFallback(entry)
            }
            self?.refresh()
        }
    }

    public func icon(for process: ProcessID) -> NSImage? {
        if let cached = icons[process] { return cached }
        let icon = NSRunningApplication(processIdentifier: process.rawValue)?.icon
        icons[process] = icon
        return icon
    }

    private func tick() {
        let trusted = AccessibilityPermission.isTrusted
        let becameTrusted = trusted && !isTrusted
        isTrusted = trusted
        guard trusted else { return }
        creationObserver.sync(Self.regularProcesses())
        refresh()
        guard becameTrusted else { return }
        refreshRequested = true
    }

    private static func regularProcesses() -> Set<ProcessID> {
        Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { ProcessID($0.processIdentifier) }
                .filter { $0 != .current }
        )
    }

    private func runRefreshes() async {
        repeat {
            refreshRequested = false
            let snapshot = await enumerator.snapshot()
            guard !Task.isCancelled else { break }
            apply(snapshot)
        } while refreshRequested
        refreshTask = nil
    }

    private func apply(_ snapshot: [WindowEntry]) {
        if snapshot != entries { entries = snapshot }
        highlight.reconcile(with: snapshot.map(\.id))
        let live = Set(snapshot.map(\.process))
        icons = icons.filter { live.contains($0.key) }
    }
}
