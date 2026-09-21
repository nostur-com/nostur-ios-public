import Foundation
import Testing
@testable import Nostur

@Suite("Web of Trust snapshot persistence")
struct WebOfTrustSnapshotStoreTests {
    private func temporaryDirectories() throws -> (root: URL, applicationSupport: URL, caches: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebOfTrustSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        let applicationSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        return (root, applicationSupport, caches)
    }

    @Test("Writes snapshots to Application Support")
    func writesToApplicationSupport() throws {
        let directories = try temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let store = WebOfTrustSnapshotStore(
            applicationSupportDirectory: directories.applicationSupport,
            cachesDirectory: directories.caches
        )
        let pubkeys: Set<String> = ["alice", "bob", "carol"]

        try store.write(pubkeys, for: "account")

        #expect(try store.read(for: "account") == pubkeys)
        #expect(FileManager.default.fileExists(
            atPath: directories.applicationSupport
                .appendingPathComponent("Nostur/web-of-trust-account.bin")
                .path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: directories.caches
                .appendingPathComponent("web-of-trust-account.bin")
                .path
        ))
    }

    @Test("Migrates an existing cache snapshot without rebuilding")
    func migratesLegacyCacheSnapshot() throws {
        let directories = try temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let pubkeys = ["alice", "bob", "carol"]
        let legacyURL = directories.caches.appendingPathComponent("web-of-trust-account.bin")
        let data = try NSKeyedArchiver.archivedData(withRootObject: pubkeys, requiringSecureCoding: false)
        try data.write(to: legacyURL)
        let store = WebOfTrustSnapshotStore(
            applicationSupportDirectory: directories.applicationSupport,
            cachesDirectory: directories.caches
        )

        #expect(store.containsSnapshot(for: "account"))
        #expect(try store.read(for: "account") == Set(pubkeys))
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(FileManager.default.fileExists(
            atPath: directories.applicationSupport
                .appendingPathComponent("Nostur/web-of-trust-account.bin")
                .path
        ))
    }

    @Test("A missing snapshot remains distinguishable from an empty snapshot")
    func reportsMissingSnapshot() throws {
        let directories = try temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let store = WebOfTrustSnapshotStore(
            applicationSupportDirectory: directories.applicationSupport,
            cachesDirectory: directories.caches
        )

        #expect(!store.containsSnapshot(for: "account"))
    }
}
