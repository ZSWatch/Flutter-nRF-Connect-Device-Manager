import Foundation

/// Terminal session admission, separate from reconnectable transport.close().
/// A completed invalidation fences even work already queued on another thread.
internal final class McuMgrBleLifetime {
    private let lock = NSLock()
    private var invalidated = false
    var isInvalidated: Bool {
        lock.lock(); defer { lock.unlock() }
        return invalidated
    }
    @discardableResult func perform(_ body: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !invalidated else { return false }
        body()
        return true
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        invalidated = true
    }
}
