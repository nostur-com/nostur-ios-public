//
//  NamecoinCertPinning.swift
//  Nostur
//
//  TOFU (trust-on-first-use) SHA-256 cert fingerprint store for ElectrumX servers.
//  Backed by UserDefaults. In-process mutations are serialized by the caller.
//

import CryptoKit
import Foundation

enum NamecoinCertPinning {
    private static let udKey = "nostur.namecoin.pinnedCerts"

    /// Compute SHA-256 fingerprint of the DER-encoded certificate, hex lowercase.
    static func fingerprint(der: Data) -> String {
        let hash = SHA256.hash(data: der)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Load all pinned fingerprints: host:port → SHA256 hex.
    static func loadAll() -> [String: String] {
        guard let dict = UserDefaults.standard.dictionary(forKey: udKey) as? [String: String] else {
            return [:]
        }
        return dict
    }

    static func pinned(for server: ElectrumXServer) -> String? {
        let key = "\(server.host):\(server.port)"
        return loadAll()[key]
    }

    /// Store a fingerprint (first-use). No-op if already stored.
    static func pinIfMissing(server: ElectrumXServer, fingerprint: String) {
        let key = "\(server.host):\(server.port)"
        var all = loadAll()
        if all[key] == nil {
            all[key] = fingerprint
            UserDefaults.standard.set(all, forKey: udKey)
            #if DEBUG
            print("[Namecoin] TOFU pinned cert for \(key): \(fingerprint.prefix(16))…")
            #endif
        }
    }

    /// Force-replace the pinned fingerprint (user action from settings).
    static func repin(server: ElectrumXServer, fingerprint: String) {
        let key = "\(server.host):\(server.port)"
        var all = loadAll()
        all[key] = fingerprint
        UserDefaults.standard.set(all, forKey: udKey)
    }

    static func clear(server: ElectrumXServer) {
        let key = "\(server.host):\(server.port)"
        var all = loadAll()
        all.removeValue(forKey: key)
        UserDefaults.standard.set(all, forKey: udKey)
    }
}
