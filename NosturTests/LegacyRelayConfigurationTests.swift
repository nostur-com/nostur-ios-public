import Foundation
import NostrEssentials
import Testing
@testable import Nostur

struct LegacyRelayConfigurationTests {
    @Test func replacementChangesRelayContentAndPreservesEveryFollowTag() throws {
        let configuration = try #require(LegacyRelayConfiguration(content: """
        {
            "wss://keep.example/": {"read": true, "write": false, "custom": "keep"},
            "wss://remove.example": {"write": true},
            "other": {"custom": "untouched"}
        }
        """))
        let latest = NEvent(publicKey: "author", createdAt: NTimestamp(timestamp: 100), content: configuration.content,
                            kind: .contactList, tags: [
                                NostrTag(["p", "followed", "wss://hint.example", "petname"]),
                                NostrTag(["t", "hashtag"]),
                                NostrTag(["custom", "value"])
                            ])

        let edited: [LegacyRelayConfiguration.Relay] = [
            .init(url: "wss://keep.example/", read: true, write: true),
            .init(url: "wss://add.example", read: false, write: true)
        ]
        let replacement = try configuration.replacementEvent(for: latest, editing: edited, now: Date(timeIntervalSince1970: 100))
        #expect(replacement.kind == .contactList)
        #expect(replacement.publicKey == latest.publicKey)
        #expect(replacement.tags.map(\.tag) == latest.tags.map(\.tag))
        #expect(replacement.createdAt.timestamp == 101)

        let updated = try #require(LegacyRelayConfiguration(content: replacement.content))
        #expect(updated.relays == edited.sorted { $0.url < $1.url })
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(replacement.content.utf8)) as? [String: [String: Any]])
        #expect(raw["wss://keep.example/"]?["custom"] as? String == "keep")
        #expect(raw["other"]?["custom"] as? String == "untouched")
        #expect(raw["wss://remove.example"] == nil)
    }

    @Test func replacementRejectsModernEventAndStaleLegacyContent() throws {
        let configuration = try #require(LegacyRelayConfiguration(content: #"{"wss://relay.example":{"read":true}}"#))
        let modernEvent = NEvent(content: configuration.content, kind: .relayList)
        let changedFollowList = NEvent(content: "{}", kind: .contactList)

        #expect(throws: (any Error).self) {
            try configuration.replacementEvent(for: modernEvent, editing: [])
        }
        #expect(throws: (any Error).self) {
            try configuration.replacementEvent(for: changedFollowList, editing: [])
        }
    }
}
