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

    @Test("Removes inactive account snapshots in both locations, preserving saved accounts and shared learned WoT")
    func removesInactiveAccounts() throws {
        let directories = try temporaryDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let store = WebOfTrustSnapshotStore(
            applicationSupportDirectory: directories.applicationSupport,
            cachesDirectory: directories.caches
        )
        let active = String(repeating: "a", count: 64)
        let otherSavedAccount = String(repeating: "b", count: 64)
        let inactive = String(repeating: "c", count: 64)
        try store.write(["alice"], for: active)
        try store.write(["bob"], for: otherSavedAccount)
        try store.write(["carol"], for: inactive)
        let oldBinary = store.legacySnapshotURL(for: inactive)
        let oldText = directories.caches.appendingPathComponent("web-of-trust-\(inactive).txt")
        try Data([1]).write(to: oldBinary)
        try Data([2]).write(to: oldText)
        let activeLegacy = directories.caches.appendingPathComponent("web-of-trust-\(active).txt")
        try Data([3]).write(to: activeLegacy)
        let shared = directories.applicationSupport.appendingPathComponent("Nostur/learned-web-of-trust.json")
        try Data([4]).write(to: shared)
        let unrelated = directories.caches.appendingPathComponent("web-of-trust-not-an-account.bin")
        try Data([5]).write(to: unrelated)

        #expect(try store.removeInactiveSnapshots(activeAccountPubkeys: [active, otherSavedAccount]) == 3)
        #expect(try store.read(for: active) == ["alice"])
        #expect(try store.read(for: otherSavedAccount) == ["bob"])
        #expect(!store.containsSnapshot(for: inactive))
        #expect(!FileManager.default.fileExists(atPath: oldBinary.path))
        #expect(!FileManager.default.fileExists(atPath: oldText.path))
        #expect(FileManager.default.fileExists(atPath: activeLegacy.path))
        #expect(FileManager.default.fileExists(atPath: shared.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(try store.removeInactiveSnapshots(activeAccountPubkeys: [active, otherSavedAccount]) == 0)
    }

}
