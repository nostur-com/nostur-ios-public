import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct SendIdentityTests {
    @Test func anon_exposes_ephemeral_pubkey() throws {
        let keys = try Keys.newKeys()
        let id = SendIdentity.anon(keys)
        #expect(id.pubkey == keys.publicKeyHex)
        #expect(id.isAnon == true)
    }
}
