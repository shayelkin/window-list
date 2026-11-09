import AppKit
import ApplicationServices

public actor WindowEnumerator {
    public static let defaultBruteForceBudget: Duration = .milliseconds(150)

    private let ownProcess: ProcessID
    private let bruteForceBudget: Duration
    private var cache: [WindowID: AXWindow] = [:]
    /// Windows a sweep already failed to find. AX elements only come into existence when a client requests them,
    /// so re-sweeping is pointless until something changes; visiting the window's Space resolves it via
    /// `kAXWindows` instead.
    private var swept: Set<WindowID> = []

    public init(excluding ownProcess: ProcessID = .current, bruteForceBudget: Duration = defaultBruteForceBudget) {
        self.ownProcess = ownProcess
        self.bruteForceBudget = bruteForceBudget
    }

    public func snapshot() async -> [WindowEntry] {
        let inventory = CGWindowInfo.inventory(excluding: ownProcess)
        let present = Set(inventory.map(\.id))
        let requests = Dictionary(grouping: inventory, by: \.process)
            .mapValues { Set($0.map(\.id)) }
            .compactMap { process, ids -> ProcessRequest? in
                guard let app = NSRunningApplication(processIdentifier: process.rawValue),
                    app.activationPolicy == .regular
                else { return nil }
                return ProcessRequest(
                    process: process,
                    appName: app.localizedName ?? "",
                    wanted: ids,
                    cached: cache.filter { ids.contains($0.key) },
                    alreadySwept: swept.intersection(ids)
                )
            }

        let budget = bruteForceBudget
        let results = await withTaskGroup(of: ProcessResult.self) { group in
            requests.forEach { request in
                group.addTask { Self.resolve(request, budget: budget) }
            }
            return await group.reduce(into: [ProcessResult]()) { $0.append($1) }
        }

        cache = results.reduce(into: [:]) { cache, result in
            result.resolved.forEach { cache[$0.id] = $0 }
        }
        swept = swept.union(results.flatMap(\.swept)).intersection(present).subtracting(cache.keys)

        return WindowOrdering.sorted(results.flatMap(\.entries) + Self.listableUnresolved(in: results))
    }

    private nonisolated static func listableUnresolved(in results: [ProcessResult]) -> [WindowEntry] {
        let currentSpaces = SpaceTopology.currentSpaces()
        let candidates = results.flatMap { result in
            result.unresolved.map { (result: result, window: $0, spaces: SpaceTopology.spaces(of: $0)) }
        }
        let hiddenSpaces = Set(candidates.flatMap(\.spaces)).subtracting(currentSpaces)
        let orderedIn = SpaceTopology.orderedInWindows(on: hiddenSpaces)
        return candidates.compactMap { candidate in
            guard
                SpaceTopology.shouldListUnresolved(
                    windowSpaces: candidate.spaces,
                    currentSpaces: currentSpaces,
                    isOrderedIn: orderedIn.contains(candidate.window)
                )
            else { return nil }
            return WindowEntry(
                unresolved: candidate.window, process: candidate.result.process, appName: candidate.result.appName)
        }
    }

    /// Finds `AXWindow`s for `wanted` by sweeping remote-token element ids upward from `start` until all are found,
    /// the id space is exhausted, or `budget` elapses. Returns the found windows and the id where the sweep stopped.
    /// Only finds windows whose AX element some client has already requested.
    /// Approach adapted from AltTab's `windowsByBruteForce`:
    /// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/AXUIElement.swift
    public nonisolated static func bruteForce(
        process: ProcessID,
        wanted: Set<WindowID>,
        from start: AXElementID = .zero,
        budget: Duration
    ) -> (found: [WindowID: AXWindow], next: AXElementID) {
        guard !wanted.isEmpty, let buffer = RemoteTokenBuffer() else { return ([:], start) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        var found: [WindowID: AXWindow] = [:]
        var current: AXElementID? = start
        while let id = current, found.count < wanted.count, clock.now < deadline {
            current = id.successor
            guard let token = buffer.load(RemoteToken(process: process, element: id)),
                let raw = PrivateAPI.element(from: token)
            else { continue }
            let element = AXElement(raw)
            guard let windowID = element.windowID, wanted.contains(windowID), found[windowID] == nil,
                let window = AXWindow(validating: element, expected: windowID)
            else { continue }
            found[windowID] = window
        }
        return (found, current ?? start)
    }

    private struct ProcessRequest: Sendable {
        let process: ProcessID
        let appName: String
        let wanted: Set<WindowID>
        let cached: [WindowID: AXWindow]
        let alreadySwept: Set<WindowID>
    }

    private struct ProcessResult: Sendable {
        let process: ProcessID
        let appName: String
        let resolved: [AXWindow]
        let entries: [WindowEntry]
        let unresolved: Set<WindowID>
        let swept: Set<WindowID>
    }

    private nonisolated static func resolve(_ request: ProcessRequest, budget: Duration) -> ProcessResult {
        let onCurrentSpace = ((try? AXApplication(process: request.process).windows()) ?? [])
            .compactMap { element -> AXWindow? in
                guard let id = element.windowID, request.wanted.contains(id) else { return nil }
                return AXWindow(validating: element, expected: id)
            }
        var windows = request.cached
        onCurrentSpace.forEach { windows[$0.id] = $0 }
        let toSweep = request.wanted.subtracting(windows.keys).subtracting(request.alreadySwept)
        windows.merge(bruteForce(process: request.process, wanted: toSweep, budget: budget).found) { _, new in new }
        let resolved = Array(windows.values)
        return ProcessResult(
            process: request.process,
            appName: request.appName,
            resolved: resolved,
            entries: resolved.compactMap { entry(for: $0, in: request) },
            unresolved: request.wanted.subtracting(windows.keys),
            swept: toSweep.subtracting(windows.keys)
        )
    }

    private nonisolated static func entry(for window: AXWindow, in request: ProcessRequest) -> WindowEntry? {
        guard let subrole = try? window.element.subrole() else { return nil }
        switch subrole {
        case .standardWindow, .dialog: break
        case .other: return nil
        }
        return WindowEntry(
            window: window,
            process: request.process,
            appName: request.appName,
            title: (try? window.element.string(kAXTitleAttribute)) ?? "",
            isMinimized: (try? window.element.bool(kAXMinimizedAttribute)) ?? false
        )
    }
}
