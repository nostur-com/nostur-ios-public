import Foundation
import Testing
import NostrEssentials
@testable import Nostur

@MainActor
struct AnonEventBuildingTests {
    @Test func anon_event_has_ephemeral_pubkey_and_no_leaky_tags() throws {
        SettingsStore.shared.postUserAgentEnabled = true
        let keys = try Keys.newKeys()
        let vm = NewPostModel()
        let built = try #require(vm.buildAnonEventForTesting(
            replyToEventId: "rootid", replyToPubkey: "authorpub",
            content: "hi :emoji:", anonPubkey: keys.publicKeyHex))
        #expect(built.publicKey == keys.publicKeyHex)
        #expect(!built.tags.contains(where: { $0.type == "client" }))
        #expect(!built.tags.contains(where: { $0.type == "emoji" }))
        #expect(!built.tags.contains(where: { $0.type == "-" }))
    }
}
