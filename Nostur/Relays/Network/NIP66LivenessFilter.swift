//
//  NIP66LivenessFilter.swift
//  Nostur
//
//  NIP-66 relay liveness pre-filter.
//  Fetches the set of online relays from nostr.watch and caches it on disk (1hr TTL).
//  Used by StochasticRelayPlanner to skip dead relays before scoring.
//

import Foundation
import NostrEssentials

class NIP66LivenessFilter {
    static let shared = NIP66LivenessFilter()

    private(set) var aliveRelays: Set<String>? = nil

    private let cacheFileName = "nip66-alive-relays.json"
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    private var cacheFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent(cacheFileName)
    }

    /// Load from disk cache if fresh, otherwise fetch from nostr.watch API.
    func loadOrFetch() {
        // Try disk cache first
        if let cached = loadFromDisk() {
            self.aliveRelays = cached
            return
        }

        // Respect VPN guard
        guard vpnGuardOK() else {
#if DEBUG
            L.sockets.debug("📡 NIP-66: Skipping fetch (VPN guard)")
#endif
            return
        }

        fetchFromAPI()
    }

    private func loadFromDisk() -> Set<String>? {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return nil }

        // Check TTL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFileURL.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < cacheTTL
        else { return nil }

        guard let data = try? Data(contentsOf: cacheFileURL),
              let urls = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }

        let normalized = Set(urls.map { normalizeRelayUrl($0) })

        // Sanity: only use if we have a healthy set (>500 relays)
        guard normalized.count > 500 else { return nil }

#if DEBUG
        L.sockets.debug("📡 NIP-66: Loaded \(normalized.count) alive relays from cache")
#endif
        return normalized
    }

    private func fetchFromAPI() {
        guard let url = URL(string: "https://api.nostr.watch/v1/online") else { return }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }

            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data,
                  let urls = try? JSONDecoder().decode([String].self, from: data)
            else {
#if DEBUG
                L.sockets.debug("📡 NIP-66: Fetch failed, aliveRelays stays nil")
#endif
                return
            }

            let normalized = Set(urls.map { normalizeRelayUrl($0) })

            // Sanity: only use if we have a healthy set (>500 relays)
            guard normalized.count > 500 else {
#if DEBUG
                L.sockets.debug("📡 NIP-66: Only \(normalized.count) relays returned, ignoring (need >500)")
#endif
                return
            }

            self.aliveRelays = normalized

            // Push to ConnectionPool so it takes effect this session
            ConnectionPool.shared.queue.async(flags: .barrier) {
                ConnectionPool.shared.aliveRelays = normalized
            }

            // Write to disk cache
            if let cacheData = try? JSONEncoder().encode(Array(normalized)) {
                try? cacheData.write(to: self.cacheFileURL)
            }

#if DEBUG
            L.sockets.debug("📡 NIP-66: Fetched \(normalized.count) alive relays from nostr.watch")
#endif
        }
        task.resume()
    }
}
