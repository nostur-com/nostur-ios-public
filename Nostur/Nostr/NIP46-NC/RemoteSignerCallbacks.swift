import Foundation

/// Signature callbacks can be registered/cancelled by UI work and consumed by
/// relay delivery. Only dictionary access is locked; execution happens outside.
final class RemoteSignerCallbacks: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [String: (NEvent) -> Void] = [:]

    func register(_ id: String, callback: @escaping (NEvent) -> Void) {
        lock.lock()
        callbacks[id] = callback
        lock.unlock()
    }

    func take(_ id: String) -> ((NEvent) -> Void)? {
        lock.lock()
        let callback = callbacks.removeValue(forKey: id)
        lock.unlock()
        return callback
    }
}
