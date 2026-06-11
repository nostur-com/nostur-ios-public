import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct AnonReplyHelperTests {
    @Test func passes_for_ephemeral_key_not_a_real_account() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, realAccountPubkeys: ["realpub"]) == true)
    }
    @Test func fails_when_pubkey_is_a_real_account() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, realAccountPubkeys: [keys.publicKeyHex]) == false)
    }
    @Test func fails_when_pubkey_is_not_the_expected_key() throws {
        let keys = try Keys.newKeys(); let other = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.publicKey = other.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, realAccountPubkeys: []) == false)
    }
}
