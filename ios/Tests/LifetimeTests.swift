import Foundation

@main struct LifetimeTests {
    static func main() {
        let lifetime = McuMgrBleLifetime()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            precondition(lifetime.perform {
                entered.signal()
                release.wait()
            })
            group.leave()
        }
        entered.wait()
        let cancelled = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { lifetime.invalidate(); cancelled.signal() }
        precondition(cancelled.wait(timeout: .now() + .milliseconds(30)) == .timedOut,
                     "Invalidation must wait for a currently admitted write")
        release.signal()
        cancelled.wait()
        group.wait()
        var writesAfterStop = 0
        for _ in 0..<1000 {
            precondition(!lifetime.perform { writesAfterStop += 1 })
        }
        precondition(writesAfterStop == 0, "Queued work cannot be admitted after Stop")
        lifetime.invalidate()
        precondition(lifetime.isInvalidated, "Cancellation is terminal and idempotent")
        let replacement = McuMgrBleLifetime()
        precondition(replacement.perform {}, "A new session has independent admission")
        print("PASS: Nordic terminal admission fences queued writes and waits for in-flight admission")
    }
}
