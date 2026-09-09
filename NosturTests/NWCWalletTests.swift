import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct NWCWalletTests {
    @Test func decodesMinimalAndFutureTransactions() throws {
        let response = try JSONDecoder().decode(NWCResponse.self, from: Data("""
        {"result_type":"list_transactions","result":{"transactions":[
          {"type":"outgoing","payment_hash":"hash","amount":1001,"created_at":1700000000,"state":"future_state","metadata":{"nostr":"wallet-specific"}},
          {"type":"incoming","payment_hash":"hash","amount":2000,"created_at":1700000001}
        ]}}
        """.utf8))
        let transactions = try #require(response.result?.transactions)
        #expect(transactions.count == 2)
        #expect(transactions[0].amount == 1001)
        #expect(transactions[0].fees_paid == nil)
        #expect(transactions[0].metadata == nil)
        #expect(transactions[0].state == "future_state")
        #expect(transactions[0].id != transactions[1].id)
    }

    @Test func identifiesOnlyZapRequestMetadata() throws {
        let transaction = try JSONDecoder().decode(NWCTransaction.self, from: Data("""
        {"type":"outgoing","payment_hash":"hash","amount":1000,"created_at":1700000000,
        "metadata":{"nostr":{"kind":9734,"pubkey":"sender","content":"Great post","tags":[["p","recipient"],["e","post"]]}}}
        """.utf8))
        #expect(transaction.zapContactPubkey == "recipient")
        #expect(transaction.zapPostId == "post")
        #expect(transaction.zapRequest?.content == "Great post")
    }

    @MainActor
    private func connection() throws -> NWCWalletClient.Connection {
        let keys = try Keys.newKeys()
        return .init(id: "wallet", walletPubkey: try Keys.newKeys().publicKeyHex,
                     pubkey: keys.publicKeyHex, secret: keys.privateKeyHex, relay: "wss://example.com", methods: [])
    }

    @Test @MainActor func matchesRequestMethodAndWallet() async throws {
        let connection = try connection()
        let (events, continuation) = AsyncStream<NEvent>.makeStream()
        let client = NWCWalletClient(activeConnectionId: { "wallet" }, publish: { continuation.yield($0) }, subscribe: { _ in })
        let task = Task { try await client.request("get_balance", connection: connection, encryption: "nip44_v2") }
        var iterator = events.makeAsyncIterator()
        let event = try #require(await iterator.next())
        let wrong = NWCResponse(result_type: "get_info", result: .init(balance: 999))
        client.receive(wrong, requestId: event.id, walletPubkey: connection.walletPubkey)
        let correct = NWCResponse(result_type: "get_balance", result: .init(balance: 123))
        client.receive(correct, requestId: "unknown", walletPubkey: connection.walletPubkey)
        client.receive(correct, requestId: event.id, walletPubkey: "other-wallet")
        client.receive(correct, requestId: event.id, walletPubkey: connection.walletPubkey)
        #expect(try await task.value.balance == 123)
        // Duplicate replies must not resume a continuation twice.
        client.receive(correct, requestId: event.id, walletPubkey: connection.walletPubkey)
    }

    @Test @MainActor func rejectsReplyAfterConnectionSwitch() async throws {
        let connection = try connection()
        var activeId = "wallet"
        let (events, continuation) = AsyncStream<NEvent>.makeStream()
        let client = NWCWalletClient(activeConnectionId: { activeId }, publish: { continuation.yield($0) }, subscribe: { _ in })
        let task = Task { try await client.request("get_balance", connection: connection, encryption: "nip04") }
        var iterator = events.makeAsyncIterator()
        let event = try #require(await iterator.next())
        activeId = "another-wallet"
        client.receive(NWCResponse(result_type: "get_balance", result: .init(balance: 123)), requestId: event.id, walletPubkey: connection.walletPubkey)
        do { _ = try await task.value; Issue.record("Accepted stale wallet response") }
        catch NWCWalletClient.Failure.disconnected { }
    }

    @Test @MainActor func timesOutWithoutResponse() async throws {
        let client = NWCWalletClient(activeConnectionId: { "wallet" }, publish: { _ in }, subscribe: { _ in }, timeoutNanoseconds: 1_000_000)
        do {
            _ = try await client.request("get_balance", connection: connection(), encryption: "nip04")
            Issue.record("Expected timeout")
        } catch NWCWalletClient.Failure.timeout { }
    }

    @Test @MainActor func cancellationRemovesPendingRequest() async throws {
        let connection = try connection()
        let (events, continuation) = AsyncStream<NEvent>.makeStream()
        let client = NWCWalletClient(activeConnectionId: { "wallet" }, publish: { continuation.yield($0) }, subscribe: { _ in })
        let task = Task { try await client.request("get_balance", connection: connection, encryption: "nip04") }
        var iterator = events.makeAsyncIterator()
        let event = try #require(await iterator.next())
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
        client.receive(NWCResponse(result_type: "get_balance", result: .init(balance: 123)), requestId: event.id, walletPubkey: connection.walletPubkey)
    }
    @Test @MainActor func negotiatesEncryptionAndDiscoversMethods() async throws {
        let connection = try connection()
        for (advertised, expected) in [("nip04 nip44_v2", "nip44_v2"), (nil, "nip04")] as [(String?, String)] {
            let (subscriptions, continuation) = AsyncStream<String>.makeStream()
            let client = NWCWalletClient(activeConnectionId: { "wallet" }, publish: { _ in }, subscribe: { continuation.yield($0) })
            var iterator = subscriptions.makeAsyncIterator()
            let task = Task { try await client.discover(connection) }
            _ = await iterator.next()
            client.receiveInfo(walletPubkey: connection.walletPubkey, methods: "get_balance list_transactions", encryption: advertised)
            let capabilities = try await task.value
            #expect(capabilities.encryption == expected)
            #expect(capabilities.methods == ["get_balance", "list_transactions"])
        }
    }

    @Test @MainActor func repeatedDiscoveryDoesNotRequireDuplicateInfoEvent() async throws {
        let connection = try connection()
        let (subscriptions, continuation) = AsyncStream<String>.makeStream()
        var subscriptionCount = 0
        let client = NWCWalletClient(activeConnectionId: { "wallet" }, publish: { _ in }, subscribe: {
            subscriptionCount += 1
            continuation.yield($0)
        }, timeoutNanoseconds: 100_000_000)
        var iterator = subscriptions.makeAsyncIterator()
        let first = Task { try await client.discover(connection) }
        _ = await iterator.next()
        client.receiveInfo(walletPubkey: connection.walletPubkey, methods: "get_balance list_transactions", encryption: "nip44_v2")
        _ = try await first.value
        // The parser drops the identical info event on later subscriptions.
        // Reopening Wallet must work even when no second event is delivered.
        for _ in 0..<3 {
            let cached = try await client.discover(connection)
            #expect(cached.methods.contains("list_transactions"))
            #expect(cached.encryption == "nip44_v2")
        }
        #expect(subscriptionCount == 1)
        client.receiveInfo(walletPubkey: connection.walletPubkey, methods: "get_balance", encryption: "nip04")
        let updated = try await client.discover(connection)
        #expect(updated.methods == ["get_balance"])
        #expect(updated.encryption == "nip04")
    }

    @Test @MainActor func setupAcknowledgementPublishesGetInfoWithoutWaitingForResponse() async throws {
        let clientKeys = try Keys.newKeys()
        let walletKeys = try Keys.newKeys()
        let connection = NWCWalletClient.Connection(
            id: "wallet",
            walletPubkey: walletKeys.publicKeyHex,
            pubkey: clientKeys.publicKeyHex,
            secret: clientKeys.privateKeyHex,
            relay: "wss://example.com",
            methods: ["get_info"]
        )
        var published: NEvent?
        let client = NWCWalletClient(
            activeConnectionId: { "wallet" },
            publish: { published = $0 },
            subscribe: { _ in Issue.record("Setup acknowledgement should not wait for a response") }
        )

        try await client.acknowledgeConnection(connection, encryption: "nip44_v2")

        let event = try #require(published)
        #expect(event.kind == .nwcRequest)
        #expect(event.publicKey == clientKeys.publicKeyHex)
        let decrypted = try #require(Keys.decryptDirectMessageContent44(
            withPrivateKey: walletKeys.privateKeyHex,
            pubkey: clientKeys.publicKeyHex,
            content: event.content
        ))
        let request = try JSONDecoder().decode(NWCRequest.self, from: Data(decrypted.utf8))
        #expect(request.method == "get_info")
    }
}
