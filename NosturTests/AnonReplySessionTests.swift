import Foundation
import Testing
@testable import Nostur

struct AnonReplySessionTests {
    @Test func tracks_registered_pubkeys() {
        let s = AnonReplySession()
        s.register("anonpub")
        #expect(s.isAnonPubkey("anonpub") == true)
        #expect(s.isAnonPubkey("other") == false)
    }
}
