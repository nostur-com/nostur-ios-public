import Foundation
import Testing
import NostrEssentials
@testable import Nostur

// @MainActor is REQUIRED: buildFinalEvent -> replaceMentionsWithNpubs -> blocks() lazily
// boots AppState.shared, whose init does a main-context Core Data fetch (loadMutedWords).
// Swift Testing runs tests off the main thread by default; without @MainActor this fetch
// runs off-main and traps with _PFAssertSafeMultiThreadedAccess. This mirrors production,
// where sendNowAnon and NewPostModel are @MainActor. Do not remove.
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
