//
//  LearnedWoTStoreTests.swift
//  NosturTests
//

import Foundation
import Testing
@testable import Nostur

struct LearnedWoTStoreTests {
    private let firstPubkey = String(repeating: "a", count: 64)
    private let secondPubkey = String(repeating: "b", count: 64)

    @Test func learnsImmediatelyAndMergesInteractionKinds() async throws {
        let fixture = try Fixture()
        let store = LearnedWoTStore(fileURL: fixture.fileURL, cloudSyncEnabled: false)
        await store.waitUntilLoadedForTesting()

        store.learn(firstPubkey, interaction: .reaction, at: Date(timeIntervalSince1970: 100))
        #expect(store.contains(firstPubkey))
        store.learn(firstPubkey, interaction: .reply, at: Date(timeIntervalSince1970: 200))
        await store.flushForTesting()

        let entry = try #require(await store.entriesForTesting().first)
        #expect(entry.pubkey == firstPubkey)
        #expect(entry.interactionKinds == [.reaction, .reply])
        #expect(entry.firstInteractionAt == Date(timeIntervalSince1970: 100))
        #expect(entry.lastInteractionAt == Date(timeIntervalSince1970: 200))
    }

    @Test func persistsAndReloadsWithoutCloudKit() async throws {
        let fixture = try Fixture()
        let firstStore = LearnedWoTStore(fileURL: fixture.fileURL, cloudSyncEnabled: false)
        await firstStore.waitUntilLoadedForTesting()
        firstStore.learn(firstPubkey, interaction: .reply)
        firstStore.learn(secondPubkey, interaction: .reaction)
        await firstStore.flushForTesting()

        let reloadedStore = LearnedWoTStore(fileURL: fixture.fileURL, cloudSyncEnabled: false)
        await reloadedStore.waitUntilLoadedForTesting()

        #expect(reloadedStore.contains(firstPubkey))
        #expect(reloadedStore.contains(secondPubkey))
        #expect(reloadedStore.currentPubkeys().count == 2)
    }

    @Test func removalPersistsAsATombstone() async throws {
        let fixture = try Fixture()
        let store = LearnedWoTStore(fileURL: fixture.fileURL, cloudSyncEnabled: false)
        await store.waitUntilLoadedForTesting()
        store.learn(firstPubkey, interaction: .reaction)
        await store.flushForTesting()

        store.remove(firstPubkey)
        #expect(!store.contains(firstPubkey))
        await store.flushForTesting()

        let reloadedStore = LearnedWoTStore(fileURL: fixture.fileURL, cloudSyncEnabled: false)
        await reloadedStore.waitUntilLoadedForTesting()
        #expect(!reloadedStore.contains(firstPubkey))
        #expect(await reloadedStore.entriesForTesting().allSatisfy(\.isRemoved))
    }

    @Test func rejectsMalformedPubkeys() async throws {
        let fixture = try Fixture()
        let store = LearnedWoTStore(fileURL: fixture.fileURL, cloudSyncEnabled: false)
        await store.waitUntilLoadedForTesting()

        store.learn("not-a-pubkey", interaction: .reply)
        store.learn(String(repeating: "z", count: 64), interaction: .reaction)
        await store.flushForTesting()

        #expect(store.currentPubkeys().isEmpty)
    }

    @Test func oneMillionLookupsStayMemoryOnly() async throws {
        let fixture = try Fixture()
        let store = LearnedWoTStore(fileURL: fixture.fileURL, cloudSyncEnabled: false)
        await store.waitUntilLoadedForTesting()
        store.learn(firstPubkey, interaction: .reply)
        await store.flushForTesting()

        let startedAt = Date()
        var matches = 0
        for _ in 0..<1_000_000 where store.contains(firstPubkey) {
            matches += 1
        }
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(matches == 1_000_000)
        #expect(elapsed < 2.0, "Learned WoT lookup unexpectedly took \(elapsed) seconds")
    }
}

private struct Fixture {
    let directoryURL: URL
    let fileURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LearnedWoTStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("learned-web-of-trust.json")
    }
}
