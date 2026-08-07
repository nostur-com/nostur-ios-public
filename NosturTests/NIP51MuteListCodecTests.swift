import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct NIP51MuteListCodecTests {
    @Test func publicMuteListRoundTrips() throws {
        let keys = try Keys.newKeys()
        let blocked = Set([
            String(repeating: "a", count: 64),
            String(repeating: "b", count: 64)
        ])

        let event = try NIP51MuteListCodec.makeUnsignedEvent(
            pubkeys: blocked,
            authorPubkey: keys.publicKeyHex,
            privacy: .publicList,
            privateKey: nil
        )
        let decoded = try NIP51MuteListCodec.decode(event, privateKey: nil)

        #expect(decoded.pubkeys == blocked)
        #expect(decoded.publicCount == 2)
        #expect(decoded.privateContentStatus == .absent)
    }

    @Test func privateMuteListRoundTripsWithNoPublicPubkeys() throws {
        let keys = try Keys.newKeys()
        let blocked = Set([
            String(repeating: "c", count: 64),
            String(repeating: "d", count: 64)
        ])

        let event = try NIP51MuteListCodec.makeUnsignedEvent(
            pubkeys: blocked,
            authorPubkey: keys.publicKeyHex,
            privacy: .privateList,
            privateKey: keys.privateKeyHex
        )
        let decoded = try NIP51MuteListCodec.decode(event, privateKey: keys.privateKeyHex)

        #expect(event.tags.isEmpty)
        #expect(!event.content.isEmpty)
        #expect(decoded.pubkeys == blocked)
        #expect(decoded.publicCount == 0)
        #expect(decoded.privateContentStatus == .decoded(2))
    }

    @Test func privateMuteListReportsMissingKeyWithoutLosingPublicItems() throws {
        let keys = try Keys.newKeys()
        let privatePubkey = String(repeating: "e", count: 64)
        let publicPubkey = String(repeating: "f", count: 64)
        var event = try NIP51MuteListCodec.makeUnsignedEvent(
            pubkeys: [privatePubkey],
            authorPubkey: keys.publicKeyHex,
            privacy: .privateList,
            privateKey: keys.privateKeyHex
        )
        event.tags.append(NostrTag(["p", publicPubkey]))

        let decoded = try NIP51MuteListCodec.decode(event, privateKey: nil)

        #expect(decoded.pubkeys == [publicPubkey])
        #expect(decoded.privateContentStatus == .keyUnavailable)
    }

    @Test func publicMergePreservesUnreadablePrivateContentAndOtherEntries() throws {
        let keys = try Keys.newKeys()
        let existingPubkey = String(repeating: "1", count: 64)
        let addedPubkey = String(repeating: "2", count: 64)
        let snapshot = NIP51MuteListSnapshot(
            publicTags: [["word", "spoiler"], ["p", existingPubkey]],
            encryptedContent: "private-content-this-device-cannot-read",
            privateTags: nil
        )

        let event = try NIP51MuteListCodec.makeMergedUnsignedEvent(
            localPubkeys: [addedPubkey],
            authorPubkey: keys.publicKeyHex,
            privacy: .publicList,
            privateKey: nil,
            existing: snapshot
        )

        #expect(event.content == snapshot.encryptedContent)
        #expect(event.tags.contains { $0.tag == ["word", "spoiler"] })
        #expect(event.tags.contains { $0.tag == ["p", existingPubkey] })
        #expect(event.tags.contains { $0.tag == ["p", addedPubkey] })
    }

    @Test func privateMergePreservesPublicAndPrivateNonAccountEntries() throws {
        let keys = try Keys.newKeys()
        let existingPubkey = String(repeating: "3", count: 64)
        let addedPubkey = String(repeating: "4", count: 64)
        let snapshot = NIP51MuteListSnapshot(
            publicTags: [["word", "public-word"]],
            encryptedContent: "previous-content",
            privateTags: [["word", "private-word"], ["p", existingPubkey]]
        )

        let event = try NIP51MuteListCodec.makeMergedUnsignedEvent(
            localPubkeys: [addedPubkey],
            authorPubkey: keys.publicKeyHex,
            privacy: .privateList,
            privateKey: keys.privateKeyHex,
            existing: snapshot
        )
        let decoded = try NIP51MuteListCodec.decode(event, privateKey: keys.privateKeyHex)

        #expect(event.tags.contains { $0.tag == ["word", "public-word"] })
        #expect(decoded.snapshot.privateTags?.contains(["word", "private-word"]) == true)
        #expect(decoded.pubkeys == [existingPubkey, addedPubkey])
    }
}
