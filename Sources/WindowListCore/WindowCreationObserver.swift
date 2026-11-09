import ApplicationServices

/// Subscribes to `kAXWindowCreatedNotification` for a set of processes. Receiving the notification makes each new
/// window's AX element exist (elements are created on first request), so it stays resolvable after it moves to
/// another Space. Notifications are delivered on the main run loop.
@MainActor
public final class WindowCreationObserver {
    private var observers: [ProcessID: AXObserver] = [:]
    private let onCreate: @MainActor (ProcessID, AXElement) -> Void

    public init(onCreate: @escaping @MainActor (ProcessID, AXElement) -> Void) {
        self.onCreate = onCreate
    }

    /// Unregisters before the memory behind each registration's unretained `refcon` is freed.
    isolated deinit { stop() }

    public var observedProcesses: Set<ProcessID> { Set(observers.keys) }

    /// Observes exactly `processes`: subscribes new ones and drops ones no longer listed.
    public func sync(_ processes: Set<ProcessID>) {
        observedProcesses.subtracting(processes).forEach(remove)
        processes.subtracting(observedProcesses).forEach(add)
    }

    public func stop() { sync([]) }

    fileprivate func deliver(_ element: AXElement) {
        guard let process = element.processID else { return }
        onCreate(process, element)
    }

    private func add(_ process: ProcessID) {
        var created: AXObserver?
        guard AXObserverCreate(process.rawValue, windowCreatedCallback, &created) == .success, let observer = created
        else { return }
        let app = AXUIElementCreateApplication(process.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon) == .success
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[process] = observer
    }

    private func remove(_ process: ProcessID) {
        guard let observer = observers.removeValue(forKey: process) else { return }
        AXObserverRemoveNotification(
            observer, AXUIElementCreateApplication(process.rawValue), kAXWindowCreatedNotification as CFString
        )
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

private func windowCreatedCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let target = Unmanaged<WindowCreationObserver>.fromOpaque(refcon).takeUnretainedValue()
    let wrapped = AXElement(element)
    MainActor.assumeIsolated { target.deliver(wrapped) }
}
