import AXTestSupport
import Foundation
import PropertyBased
import Testing

private final class Slot<T>: @unchecked Sendable {
    var value: T?
}

private struct Unchecked<T>: @unchecked Sendable {
    let value: T
}

/// Runs `body` on a fresh thread; `nil` when it has not returned within `timeout`, so a hang fails instead of stalling.
private func onNewThread<T>(timeout: DispatchTimeInterval, _ body: @escaping () throws -> T) throws -> T? {
    let finished = DispatchSemaphore(value: 0)
    let slot = Slot<Result<T, any Error>>()
    let work = Unchecked(value: body)
    Thread.detachNewThread {
        slot.value = Result { try work.value() }
        finished.signal()
    }
    guard finished.wait(timeout: .now() + timeout) == .success, let result = slot.value else { return nil }
    return try result.get()
}

extension LiveAXTests {
    /// Async tests hop threads between launching a fixture and terminating it.
    @Suite struct FixtureLifecycle {
        static let bound: DispatchTimeInterval = .seconds(15)

        @Test func terminateReturnsWhenLaunchedOnAnotherThread() async {
            await propertyCheck(count: 10, input: Gen.int(in: 0...3)) { windows in
                await Live.failOnThrow {
                    let launched = try #require(
                        try onNewThread(timeout: Self.bound) { Unchecked(value: try Fixture()) },
                        "launching a fixture must return within \(Self.bound)")
                    let fixture = launched.value
                    try (0..<windows).forEach { _ = try fixture.open(title: "w\($0)") }
                    let returned = try onNewThread(timeout: Self.bound) { fixture.terminate() } != nil
                    #expect(returned, "terminate() must return within \(Self.bound) with \(windows) windows open")
                    #expect(!fixture.isRunning, "a terminated fixture must not be running")
                    #expect(
                        kill(fixture.process.rawValue, 0) == -1 && errno == ESRCH,
                        "a terminated fixture must be reaped, not left as a zombie")
                }
            }
        }
    }
}
