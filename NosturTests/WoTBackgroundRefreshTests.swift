import Foundation
import Testing
import NostrEssentials
@testable import Nostur

@Suite("Charging Web of Trust maintenance", .serialized)
struct WoTBackgroundRefreshTests {
    @Test("Resuming preserves completed lists and removes stale trust edges")
    func checkpointRoundTrip() throws {
        var checkpoint = WoTRefreshCheckpoint(account: "main", authors: ["alice", "bob"], dunbarNumber: 2,
            pending: ["bob"], lists: ["alice": .init(createdAt: 1, follows: ["old"])])
        checkpoint = try JSONDecoder().decode(WoTRefreshCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        #expect(checkpoint.pending == ["bob"])
        checkpoint.merge(["alice": .init(createdAt: 2, follows: ["new"]), "bob": .init(createdAt: 2, follows: ["a", "b", "c"])])
        checkpoint.merge(["alice": .init(createdAt: 1, follows: ["old"])])
        #expect(checkpoint.allowed == ["new"])
    }

    @Test("Signed lists require EOSE; the most recent list wins")
    func signedResponse() async throws {
        let keys = try Keys.newKeys()
        let inbox = WoTRefreshRelayInbox()
        let relay = "wss://wot-test.example"
        var older = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: 1), kind: .contactList,
            tags: [Nostur.NostrTag(["p", "old"])])
        older = try older.sign(keys)
        var newer = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: 2), kind: .contactList,
            tags: [Nostur.NostrTag(["p", "new"])])
        newer = try newer.sign(keys)
        let lists = try await inbox.collect(authors: [keys.publicKeyHex], relay: relay, send: { id in
            inbox.route(text: "[\"EVENT\",\"\(id)\",\(newer.eventJson())]", relay: relay)
            inbox.route(text: "[\"EVENT\",\"\(id)\",\(older.eventJson())]", relay: relay)
            inbox.route(text: "[\"EOSE\",\"\(id)\"]", relay: relay)
        })
        #expect(lists[keys.publicKeyHex]?.follows == ["new"])
    }

    @Test("CLOSED and missing EOSE never count as a successful refresh")
    func incompleteResponses() async {
        let inbox = WoTRefreshRelayInbox()
        do {
            _ = try await inbox.collect(authors: ["alice"], relay: "wss://wot-test.example", send: { id in
                inbox.route(text: "[\"CLOSED\",\"\(id)\",\"blocked\"]", relay: "wss://wot-test.example")
            })
            Issue.record("CLOSED should fail")
        } catch { }
        do {
            _ = try await inbox.collect(authors: ["alice"], relay: "wss://wot-test.example", timeout: 0.1, send: { _ in })
            Issue.record("No EOSE should time out")
        } catch { }
    }


    @Test("Invalid signatures and response limits fail even when followed by EOSE")
    func rejectsInvalidResponses() async throws {
        let keys = try Keys.newKeys()
        var tampered = NEvent(publicKey: keys.publicKeyHex, kind: .contactList)
        tampered = try tampered.sign(keys)
        tampered.content = "modified after signing"
        let inbox = WoTRefreshRelayInbox()
        for oversized in [false, true] {
            do {
                _ = try await inbox.collect(authors: [keys.publicKeyHex], relay: "wss://wot-test.example", send: { id in
                    let payload = oversized ? String(repeating: "x", count: 512_001) : tampered.eventJson()
                    inbox.route(text: "[\"EVENT\",\"\(id)\",\(payload)]", relay: "wss://wot-test.example")
                    inbox.route(text: "[\"EOSE\",\"\(id)\"]", relay: "wss://wot-test.example")
                })
                Issue.record("Invalid or oversized responses should fail")
            } catch { }
        }
    }

    @Test("Maintenance cancellation completes promptly while the importer context is held")
    func cancellationWhileImporterBusy() async throws {
        let release = DispatchSemaphore(value: 0)
        let context = await MainActor.run { bg() }
        await withCheckedContinuation { continuation in
            context.perform {
                continuation.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        defer { release.signal() }
        let inbox = WoTRefreshRelayInbox()
        let responseStart = Date()
        let result = try await inbox.collect(authors: ["alice"], relay: "wss://wot-test.example", send: { id in
            inbox.route(text: "[\"EOSE\",\"\(id)\"]", relay: "wss://wot-test.example")
        })
        #expect(result.isEmpty)
        #expect(Date().timeIntervalSince(responseStart) < 0.5)
        let work = Task {
            try await inbox.collect(authors: ["alice"], relay: "wss://wot-test.example", send: { _ in })
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let start = Date()
        work.cancel()
        do { _ = try await work.value; Issue.record("Cancellation should fail") }
        catch { #expect(error is CancellationError) }
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(!inbox.route(text: "[\"EOSE\",\"ordinary-feed\"]", relay: "wss://wot-test.example"))
    }
}
