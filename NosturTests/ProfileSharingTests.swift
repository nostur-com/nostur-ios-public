import XCTest
import NostrEssentials
@testable import Nostur

final class ProfileSharingTests: XCTestCase {
    private let pubkey = String(repeating: "ab", count: 32)

    func testSharedProfileRoundTripsWithRelayHints() throws {
        let identifier = try NostrEssentials.ShareableIdentifier("nprofile", pubkey: pubkey, relays: ["wss://relay.example.com"])
        let parsed = try XCTUnwrap(ScannedProfile.parse("nostr:" + identifier.identifier))
        XCTAssertEqual(parsed.pubkey, pubkey)
        XCTAssertEqual(parsed.relays, ["wss://relay.example.com"])
    }

    func testNpubAndNonProfileCodes() throws {
        let identifier = try NostrEssentials.ShareableIdentifier("npub", pubkey: pubkey)
        XCTAssertEqual(ScannedProfile.parse(identifier.identifier)?.pubkey, pubkey)
        XCTAssertNil(ScannedProfile.parse("https://example.com"))
        XCTAssertNil(ScannedProfile.parse("nostr:nsec1invalid"))
        XCTAssertNil(ScannedProfile.parse("nostr:nprofile1invalid"))
    }

    func testRelayHintsAreValidatedDeduplicatedAndBounded() {
        XCTAssertEqual(ScannedProfile.relayHints([
            "https://example.com", "wss://user:password@relay.example.com",
            "wss://a.example.com", "wss://a.example.com/", "wss://b.example.com",
            "wss://c.example.com", "wss://d.example.com"
        ]), ["wss://a.example.com", "wss://b.example.com", "wss://c.example.com"])
        XCTAssertTrue(ScannedProfile.relayHints(["wss://" + String(repeating: "a", count: 256)]).isEmpty)
    }

    func testMalformedTLVDoesNotCrash() {
        for data in [Data([0, 32, 1]), Data([0, 1, 0]), Data([1, 1, 255]), Data([0])] {
            let code = Bech32().encode("nprofile", values: data, eightToFive: true)
            XCTAssertNil(ScannedProfile.parse(code))
        }
    }

    func testUnknownTLVsAreIgnored() {
        var data = Data([0, 32])
        data.append(contentsOf: Array(repeating: UInt8(0xab), count: 32))
        data.append(contentsOf: [99, 1, 42])
        XCTAssertEqual(ScannedProfile.parse(Bech32().encode("nprofile", values: data, eightToFive: true))?.pubkey, pubkey)
    }
}
