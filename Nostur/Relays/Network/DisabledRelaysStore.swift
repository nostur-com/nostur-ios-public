//
//  DisabledRelaysStore.swift
//  Nostur
//
//  Created by Codex on 22/04/2026.
//

import Foundation
import NostrEssentials

extension Notification.Name {
    static let disabledRelaysDidChange = Notification.Name("disabledRelaysDidChange")
}

enum DisabledRelaysStore {
    private static let key = "disabled_relays"
    private static let state = State()

    static func all() -> [CanonicalRelayUrl] {
        ensureCacheLoaded()
        return state.all()
    }

    static func count() -> Int {
        ensureCacheLoaded()
        return state.count()
    }

    static func isDisabled(_ relayUrl: String) -> Bool {
        ensureCacheLoaded()
        let relayId = normalizeRelayUrl(relayUrl)
        return state.contains(relayId)
    }

    static func setDisabled(_ relayUrl: String, isDisabled: Bool) {
        ensureCacheLoaded()
        let relayId = normalizeRelayUrl(relayUrl)
        let relaysToPersist = state.set(relayId: relayId, isDisabled: isDisabled)
        UserDefaults.standard.set(relaysToPersist, forKey: key)
        NotificationCenter.default.post(name: .disabledRelaysDidChange, object: nil)
    }

    static func refreshFromStorage() {
        let stored = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        let normalized = Set(stored.map { normalizeRelayUrl($0) })
        updateCache(normalized)
    }

    private static func ensureCacheLoaded() {
        guard !state.isLoaded() else { return }
        refreshFromStorage()
    }

    private static func updateCache(_ value: Set<CanonicalRelayUrl>) {
        state.update(value)
    }

    private final class State {
        private let lock = NSLock()
        private var loaded = false
        private var cachedSet: Set<CanonicalRelayUrl> = []

        func isLoaded() -> Bool {
            lock.withLock { loaded }
        }

        func all() -> [CanonicalRelayUrl] {
            lock.withLock { Array(cachedSet) }
        }

        func count() -> Int {
            lock.withLock { cachedSet.count }
        }

        func contains(_ relayId: CanonicalRelayUrl) -> Bool {
            lock.withLock { cachedSet.contains(relayId) }
        }

        func set(relayId: CanonicalRelayUrl, isDisabled: Bool) -> [CanonicalRelayUrl] {
            lock.withLock {
                if isDisabled {
                    cachedSet.insert(relayId)
                }
                else {
                    cachedSet.remove(relayId)
                }
                return Array(cachedSet)
            }
        }

        func update(_ value: Set<CanonicalRelayUrl>) {
            lock.withLock {
                cachedSet = value
                loaded = true
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
