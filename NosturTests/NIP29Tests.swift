import Foundation
import Testing
@testable import Nostur

@MainActor
@Suite("NIP-29 groups")
struct NIP29Tests {
    private let relay = "wss://groups.example.com"
    private let account = String(repeating: "a", count: 64)

    @Test("Group requests are scoped to h and relay metadata")
    func requestFilters() throws {
        let address = NIP29GroupAddress(relayURL: relay + "/", groupId: "pizza")
        let message = NIP29Protocol.subscriptionMessage(
            address: address,
            subscriptionId: "group-sub",
            limit: 50
        )
        let data = try #require(message.data(using: .utf8))
        let command = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(command[0] as? String == "REQ")
        #expect(command[1] as? String == "group-sub")

        let timelineFilter = try #require(command[2] as? [String: Any])
        #expect(timelineFilter["#h"] as? [String] == ["pizza"])
        #expect(timelineFilter["limit"] as? Int == 50)

        let metadataFilter = try #require(command[3] as? [String: Any])
        #expect(metadataFilter["#d"] as? [String] == ["pizza"])
        #expect(Set(metadataFilter["kinds"] as? [Int] ?? []) == NIP29Kind.relayGeneratedKinds)
        #expect(address.relayURL == relay)
    }

    @Test("Chat events contain group and bounded timeline references")
    func chatEventTags() {
        let address = NIP29GroupAddress(relayURL: relay, groupId: "nostr")
        let ids = [
            "11111111aaaaaaaa", "22222222bbbbbbbb", "33333333cccccccc", "44444444dddddddd"
        ]
        let event = NIP29Protocol.chatEvent(
            content: "hello",
            address: address,
            previousEventIds: ids
        )

        #expect(event.kind.id == NIP29Kind.chatMessage)
        #expect(event.tags.first?.tag == ["h", "nostr"])
        #expect(event.tags.filter { $0.type == "previous" }.map(\.tag) == [
            ["previous", "22222222"],
            ["previous", "33333333"],
            ["previous", "44444444"]
        ])
    }

    @Test("Store publishes sorted immutable snapshots and ignores duplicates")
    func snapshotUpdates() {
        let store = NIP29Store(maximumTimelineCount: 3)
        let address = NIP29GroupAddress(relayURL: relay, groupId: "group")

        store.ingest(metadataEvent(groupId: "group"), from: address, accountPubkey: account)
        store.ingest(membersEvent(groupId: "group", members: [account]), from: address, accountPubkey: account)
        store.ingest(chatEvent(id: "late", groupId: "group", pubkey: "b", createdAt: 20), from: address, accountPubkey: account)
        store.ingest(chatEvent(id: "early", groupId: "group", pubkey: "c", createdAt: 10), from: address, accountPubkey: account)
        store.ingest(chatEvent(id: "late", groupId: "group", pubkey: "b", createdAt: 20), from: address, accountPubkey: account)

        let snapshot = store.snapshot(for: address)
        #expect(snapshot.metadata?.name == "Test group")
        #expect(snapshot.metadata?.isRestricted == true)
        #expect(snapshot.isMember)
        #expect(snapshot.timeline.map(\.id) == ["early", "late"])
    }

    @Test("Timeline references exclude the current user's own events")
    func previousReferences() {
        let store = NIP29Store()
        let address = NIP29GroupAddress(relayURL: relay, groupId: "group")
        store.ingest(chatEvent(id: "11111111", groupId: "group", pubkey: account, createdAt: 1), from: address, accountPubkey: account)
        store.ingest(chatEvent(id: "22222222", groupId: "group", pubkey: "b", createdAt: 2), from: address, accountPubkey: account)
        store.ingest(chatEvent(id: "33333333", groupId: "group", pubkey: "c", createdAt: 3), from: address, accountPubkey: account)

        #expect(store.previousEventIds(for: address, excludingPubkey: account) == ["22222222", "33333333"])
    }

    @Test("One account reuses one socket per relay")
    func sessionReuse() throws {
        var transports: [NIP29SessionKey: MockNIP29Transport] = [:]
        let service = NIP29Service { key in
            let transport = MockNIP29Transport()
            transports[key] = transport
            return transport
        }
        let first = NIP29GroupAddress(relayURL: relay, groupId: "one")
        let second = NIP29GroupAddress(relayURL: relay, groupId: "two")

        try service.subscribe(to: first, accountPubkey: account)
        #expect(transports.count == 1)

        let transport = try #require(transports.values.first)
        transport.emit(.connected)
        #expect(transport.sentMessages.count == 1)

        try service.subscribe(to: second, accountPubkey: account)
        #expect(transports.count == 1)
        #expect(transport.sentMessages.count == 2)
        #expect(transport.connectCount == 1)

        try service.subscribe(to: first, accountPubkey: String(repeating: "b", count: 64))
        #expect(transports.count == 2)
    }

    @Test("Persistence keys keep relay forks and accounts separate")
    func persistenceKeys() {
        let original = NIP29GroupAddress(relayURL: relay, groupId: "group|with|separators")
        let fork = NIP29GroupAddress(relayURL: "wss://fork.example.com", groupId: original.groupId)
        let otherAccount = String(repeating: "b", count: 64)

        let originalAddressKey = NIP29EventContext.makeAddressKey(accountPubkey: account, address: original)
        let forkAddressKey = NIP29EventContext.makeAddressKey(accountPubkey: account, address: fork)
        let otherAccountKey = NIP29EventContext.makeAddressKey(accountPubkey: otherAccount, address: original)

        #expect(originalAddressKey != forkAddressKey)
        #expect(originalAddressKey != otherAccountKey)
        #expect(
            NIP29EventContext.makeContextKey(accountPubkey: account, address: original, eventId: "one")
                != NIP29EventContext.makeContextKey(accountPubkey: account, address: original, eventId: "two")
        )
    }

    private func metadataEvent(groupId: String) -> NEvent {
        NEvent(
            id: "metadata",
            publicKey: String(repeating: "f", count: 64),
            content: "",
            kind: .custom(NIP29Kind.groupMetadata),
            tags: [
                NostrTag(["d", groupId]),
                NostrTag(["name", "Test group"]),
                NostrTag(["restricted"])
            ]
        )
    }

    private func membersEvent(groupId: String, members: [String]) -> NEvent {
        NEvent(
            id: "members",
            publicKey: String(repeating: "f", count: 64),
            content: "",
            kind: .custom(NIP29Kind.groupMembers),
            tags: [NostrTag(["d", groupId])] + members.map { NostrTag(["p", $0]) }
        )
    }

    private func chatEvent(id: String, groupId: String, pubkey: String, createdAt: Int) -> NEvent {
        NEvent(
            id: id,
            publicKey: pubkey,
            createdAt: NTimestamp(timestamp: createdAt),
            content: id,
            kind: .custom(NIP29Kind.chatMessage),
            tags: [NostrTag(["h", groupId])]
        )
    }
}

private final class MockNIP29Transport: NIP29RelayTransport {
    var onTextFrame: ((String) -> Void)?
    var onStateChange: ((NIP29ConnectionState) -> Void)?
    var connectCount = 0
    var sentMessages: [String] = []

    func connect() { connectCount += 1 }
    func send(_ text: String) { sentMessages.append(text) }
    func disconnect() {}
    func emit(_ state: NIP29ConnectionState) { onStateChange?(state) }
}
