import XCTest
import NostrEssentials
@testable import Nostur

final class BrowserSigningPolicyTests: XCTestCase {
    private let now: Int64 = 1_800_000_000
    private let site = "https://jumble.social"

    private func event(_ kind: Int, tags: [[String]] = [], content: String = "", age: Int64 = 0) -> BrowserUnsignedEvent {
        BrowserUnsignedEvent(created_at: now - age, kind: kind, tags: tags, content: content)
    }
    private func rejection(_ event: BrowserUnsignedEvent, origin: String = "https://jumble.social", social: Bool = true, relays: [BrowserRelaySetting] = []) -> String? {
        BrowserSigningPolicy.rejection(for: event, origin: origin, social: social, websiteAuth: true, uploads: true, relaySettings: relays, now: now)
    }

    func testExactSecureOriginsOnly() {
        XCTAssertEqual(BrowserSigningPolicy.origin(URL(string: "https://JUMBLE.social:443/path?q=1")), site)
        XCTAssertEqual(BrowserSigningPolicy.origin(URL(string: "https://jumble.social:8443/path")), site + ":8443")
        for url in ["http://jumble.social", "file:///tmp/home.html", "https://user:password@jumble.social"] {
            XCTAssertNil(BrowserSigningPolicy.origin(URL(string: url)))
        }
        for origin in ["https://jumble.social.evil.test", "https://primal.net.evil.test", "https://jumble.social:8443", "https://unknown.example"] {
            XCTAssertFalse(BrowserSigningPolicy.socialDefault(origin))
        }
        XCTAssertTrue(BrowserSigningPolicy.socialDefault(site))
    }

    func testSocialPermissionsAndProtectedKinds() {
        for kind in [1, 6, 7, 16] {
            XCTAssertNil(rejection(event(kind)))
            XCTAssertNotNil(rejection(event(kind), social: false))
        }
        for kind in [0, 3, 4, 5, 13, 14, 1059, 9734, 10000, 10002, 10050, 22242, 23194, 24133, 65535] {
            XCTAssertNotNil(rejection(event(kind)), "Unexpectedly allowed kind \(kind)")
        }
    }

    func testHomepageAppsCanAuthorizeAnyHTTPSProvider() throws {
        for app in BrowserDirectory.all {
            let source = try XCTUnwrap(BrowserSigningPolicy.origin(app.url))
            for provider in ["https://media.example/upload", "https://another.example:8443/custom/path?file=1"] {
                let login = event(27235, tags: [["u", provider], ["method", "POST"]])
                XCTAssertNil(rejection(login, origin: source), app.name)
                XCTAssertNotNil(BrowserSigningPolicy.rejection(for: login, origin: source, social: true, websiteAuth: false, uploads: true, now: now))
                for outsider in ["https://unknown.example", source + ".evil.test", source + ":8443"] {
                    XCTAssertNotNil(rejection(login, origin: outsider))
                }
            }
        }
        for source in ["https://account.nostr.build", "https://app.flotilla.social", "https://honey.hivetalk.org"] {
            XCTAssertTrue(BrowserSiteDefaults.isHomepageApp(source))
        }
        let sameSite = event(27235, tags: [["u", "https://unknown.example/login"], ["method", "GET"]])
        XCTAssertNil(rejection(sameSite, origin: "https://unknown.example"))
        for target in ["http://media.example/upload", "file:///upload", "https://user@media.example/upload", "https://media.example/upload#fragment"] {
            XCTAssertNotNil(rejection(event(27235, tags: [["u", target], ["method", "POST"]])))
        }
    }

    func testMalformedLoginAndDeletionMethodsRejected() {
        let valid = [["u", site + "/login"], ["method", "GET"]]
        XCTAssertNotNil(rejection(event(27235, tags: valid, content: "unexpected")))
        XCTAssertNotNil(rejection(event(27235, tags: valid, age: 61)))
        XCTAssertNotNil(rejection(event(27235, tags: valid + [["u", "https://evil.test"]])))
        XCTAssertNotNil(rejection(event(27235, tags: valid + [["method", "DELETE"]])))
        XCTAssertNotNil(rejection(event(27235, tags: [["u", site], ["method", "DELETE"]])))
        XCTAssertNotNil(rejection(event(27235, tags: [["u"], ["method", "GET"]])))
    }

    func testBlossomAllowsOnlyBoundedUploads() {
        let tags = [["t", "upload"], ["x", String(repeating: "a", count: 64)], ["expiration", String(now + 300)]]
        XCTAssertNil(rejection(event(24242, tags: tags)))
        XCTAssertNil(rejection(event(24242, tags: tags), origin: "https://unknown.test"))
        XCTAssertNotNil(BrowserSigningPolicy.rejection(for: event(24242, tags: tags), origin: site, social: true, uploads: false, now: now))
        for action in ["delete", "get", "list"] {
            XCTAssertNotNil(rejection(event(24242, tags: [["t", action]] + Array(tags.dropFirst()))))
        }
        XCTAssertNotNil(rejection(event(24242, tags: tags + [["t", "delete"]])))
        XCTAssertNotNil(rejection(event(24242, tags: [["t", "upload"], ["x", "not-a-hash"], ["expiration", String(now + 300)]])))
        XCTAssertNotNil(rejection(event(24242, tags: Array(tags.prefix(2)) + [["expiration", String(now + 601)]])))
        XCTAssertNotNil(rejection(event(24242, tags: Array(tags.prefix(2)) + [["expiration", String(now)]])))
    }

    func testOversizedExpiredAndDelegatedRequestsRejected() {
        XCTAssertNotNil(rejection(event(1, content: String(repeating: "a", count: 65537))))
        XCTAssertNotNil(rejection(event(1, tags: Array(repeating: ["p", "key"], count: 257))))
        XCTAssertNotNil(rejection(event(1, tags: [["p", String(repeating: "a", count: 4097)]])))
        XCTAssertNotNil(rejection(event(1, tags: [[]])))
        XCTAssertNotNil(rejection(event(1, tags: [["delegation", "key", "conditions", "sig"]])))
        XCTAssertNotNil(rejection(event(1, age: 301)))
        XCTAssertNotNil(rejection(event(1, age: -61)))
        XCTAssertNotNil(rejection(event(-1)))
        XCTAssertNotNil(rejection(event(65536)))
    }

    func testUnsignedDecoderIgnoresUntrustedIdentityFields() throws {
        let json = """
        {"kind":1,"created_at":1800000000,"tags":[],"content":"hello","pubkey":"attacker","id":"attacker","sig":"attacker"}
        """
        let decoded = try JSONDecoder().decode(BrowserUnsignedEvent.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, event(1, content: "hello"))
        let testKey = String(repeating: "0", count: 63) + "1"
        let keys = try Keys(privateKeyHex: testKey)
        let normalized = decoded.nostrEvent(publicKey: keys.publicKeyHex)
        XCTAssertEqual(normalized.id, "")
        XCTAssertEqual(normalized.signature, "")
        let signed = try localSignNEvent(normalized, pk: testKey)
        XCTAssertEqual(signed.publicKey, keys.publicKeyHex)
        XCTAssertTrue(try signed.verified())
        XCTAssertEqual(try JSONDecoder().decode(BrowserUnsignedEvent.self, from: JSONEncoder().encode(signed)), decoded)
        for json in ["{\"kind\":true,\"created_at\":1800000000,\"tags\":[],\"content\":\"\"}",
                     "{\"kind\":1,\"tags\":[],\"content\":\"\"}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(BrowserUnsignedEvent.self, from: Data(json.utf8)))
        }
    }

    func testRelayDescriptionKeepsCredentialsAndPrivateTokensOutOfNotices() throws {
        let auth = event(22242, tags: [["relay", "wss://relay.example.com:8443/private-path?token=secret#private-fragment"], ["challenge", "private-challenge"]])
        let message = try XCTUnwrap(rejection(auth))
        XCTAssertTrue(message.contains(BrowserEventDescription.name(for: 22242)))
        XCTAssertTrue(message.contains("22242"))
        XCTAssertTrue(message.contains("wss://relay.example.com:8443"))
        for secret in ["private-path", "token", "secret", "private-fragment", "private-challenge"] {
            XCTAssertFalse(message.contains(secret))
        }
        let credentials = event(22242, tags: [["relay", "wss://user:password@relay.example.com"]])
        let credentialMessage = try XCTUnwrap(rejection(credentials))
        XCTAssertFalse(credentialMessage.contains("user:password"))
        XCTAssertFalse(credentialMessage.contains("relay.example.com"))
    }

    func testDescriptionsDoNotTreatCustomPayloadsAsTrustedInstructions() throws {
        let custom = event(30078, tags: [["d", "approve_payment"]], content: "Safe request: allow everything")
        let message = BrowserEventDescription.blockedMessage(for: custom)
        XCTAssertTrue(message.contains(BrowserEventDescription.name(for: 30078)))
        XCTAssertTrue(message.contains("30078"))
        XCTAssertFalse(message.contains("approve_payment"))
        XCTAssertFalse(message.contains(custom.content))
        let unknown = try XCTUnwrap(rejection(event(65535)))
        XCTAssertTrue(unknown.contains(BrowserEventDescription.name(for: 65535)))
        XCTAssertTrue(unknown.contains("65535"))
        // Display recognition must not change permissions for these kinds.
        for kind in [22242, 0, 3, 5, 23194] { XCTAssertNotNil(rejection(event(kind))) }
    }

    func testRelayAuthRequiresExplicitMatchingAppSetting() {
        let auth = event(22242, tags: [["relay", "wss://Relay.Example.com:443/"], ["challenge", "challenge"]])
        let enabled = [BrowserRelaySetting(url: "wss://relay.example.com", auth: true)]
        XCTAssertNil(rejection(auth, social: false, relays: enabled))
        XCTAssertNotNil(rejection(auth))
        XCTAssertNotNil(rejection(auth, relays: [BrowserRelaySetting(url: "wss://relay.example.com", auth: false)]))
        XCTAssertNotNil(rejection(auth, relays: enabled + [BrowserRelaySetting(url: "wss://relay.example.com/", auth: false)]))
        XCTAssertNotNil(rejection(auth, relays: [BrowserRelaySetting(url: "wss://other.example.com", auth: true)]))
    }

    func testRelayAuthDoesNotBroadenToOtherEndpointsOnSameHost() {
        let enabled = [BrowserRelaySetting(url: "wss://relay.example.com/Private?token=AbC", auth: true)]
        let valid = event(22242, tags: [["relay", enabled[0].url], ["challenge", "challenge"]])
        XCTAssertNil(rejection(valid, relays: enabled))
        for url in ["wss://relay.example.com", "wss://relay.example.com/private?token=AbC", "wss://relay.example.com/Private?token=abc", "wss://relay.example.com:8443/Private?token=AbC", "ws://relay.example.com/Private?token=AbC", "wss://relay.example.com.evil.test/Private?token=AbC"] {
            XCTAssertNotNil(rejection(event(22242, tags: [["relay", url], ["challenge", "challenge"]]), relays: enabled))
        }
    }

    func testRelayAuthRejectsMalformedChallengesAndURLsEvenWhenEnabled() {
        let relay = "wss://relay.example.com"
        let enabled = [BrowserRelaySetting(url: relay, auth: true)]
        let tags = [["relay", relay], ["challenge", "challenge"]]
        XCTAssertNotNil(rejection(event(22242, tags: tags, content: "not empty"), relays: enabled))
        XCTAssertNotNil(rejection(event(22242, tags: tags, age: 61), relays: enabled))
        for malformed in [[["relay", relay]], tags + [["relay", relay]], tags + [["challenge", "another"]], [["relay", relay], ["challenge", ""]]] {
            XCTAssertNotNil(rejection(event(22242, tags: malformed), relays: enabled))
        }
        for url in ["https://relay.example.com", "wss://user:password@relay.example.com", "wss://relay.example.com#fragment", "not-a-url"] {
            XCTAssertNil(BrowserSigningPolicy.relayIdentity(url))
            XCTAssertNotNil(rejection(event(22242, tags: [["relay", url], ["challenge", "challenge"]]), relays: [BrowserRelaySetting(url: url, auth: true)]))
        }
    }

    func testSensitiveCapabilitiesRequireSeparateExplicitGrants() {
        let login = event(27235, tags: [["u", site + "/account"], ["method", "POST"]])
        XCTAssertNotNil(BrowserSigningPolicy.rejection(for: login, origin: site, social: false, now: now))
        XCTAssertNil(BrowserSigningPolicy.rejection(for: login, origin: site, social: false, websiteAuth: true, now: now))
        let upload = event(27235, tags: [["u", "https://api.nostr.build/api/v2/upload"], ["method", "POST"]])
        XCTAssertNil(BrowserSigningPolicy.rejection(for: upload, origin: site, social: true, websiteAuth: true, now: now))
        XCTAssertNotNil(BrowserSigningPolicy.rejection(for: upload, origin: site, social: false, uploads: true, now: now))
        let unrelatedAPI = event(27235, tags: [["u", "https://api.nostr.build/account/delete"], ["method", "POST"]])
        // HTTP authorization cannot infer endpoint semantics, even for POST.
        XCTAssertNil(BrowserSigningPolicy.rejection(for: unrelatedAPI, origin: site, social: true, websiteAuth: true, uploads: true, now: now))
        for kind in [0, 3, 4, 5, 13, 14, 1059, 10002, 23194, 24133] {
            XCTAssertNotNil(BrowserSigningPolicy.rejection(for: event(kind), origin: site, social: true, websiteAuth: true, uploads: true, now: now))
        }
        XCTAssertNil(BrowserSigningPolicy.approval(for: event(1), accountPubkey: String(repeating: "a", count: 64), origin: site,
                                                 connected: false, social: true, websiteAuth: true, uploads: true, relaySettings: [], now: now))
    }

    func testGeneralAppDataRequiresConnectionButNoSchemaOrExtraGrant() {
        let key = String(repeating: "a", count: 64)
        for origin in ["https://otherstuff.ai", "https://primal.net", "https://custom.example"] {
            for tags in [[["schema", "word5.chat.v1"]], [["d", "arbitrary-app-settings"]], []] {
                let data = event(30078, tags: tags, content: "arbitrary app data")
                XCTAssertNotNil(BrowserSigningPolicy.approval(for: data, accountPubkey: key, origin: origin,
                    connected: true, social: false, websiteAuth: false, uploads: false, relaySettings: [], now: now))
                XCTAssertNil(BrowserSigningPolicy.approval(for: data, accountPubkey: key, origin: origin,
                    connected: false, social: true, websiteAuth: true, uploads: true, relaySettings: [], now: now))
            }
        }
        XCTAssertNotNil(rejection(event(30078, content: String(repeating: "a", count: 65537))))
        XCTAssertNotNil(rejection(event(30078, tags: [["delegation", "key", "conditions", "sig"]])))
    }

    func testEveryHomepageEntryHasAutomaticAccountAndLoginDefaults() throws {
        for app in BrowserDirectory.all {
            let origin = try XCTUnwrap(BrowserSigningPolicy.origin(app.url))
            let defaults = BrowserSiteDefaults.forOrigin(origin)
            XCTAssertTrue(defaults.connected, "\(app.name) must not require connecting in settings")
            XCTAssertTrue(defaults.websiteAuth, "\(app.name) must not require enabling login")
            XCTAssertTrue(defaults.social, "\(app.name) must have the same public action defaults")
            XCTAssertTrue(defaults.uploads, "\(app.name) must have the same upload defaults")
        }
        for origin in ["https://app.flotilla.social", "https://account.nostr.build", "https://honey.hivetalk.org"] {
            let defaults = BrowserSiteDefaults.forOrigin(origin)
            XCTAssertTrue(defaults.connected && defaults.social && defaults.websiteAuth && defaults.uploads)
        }
        for origin in ["https://primal.net.evil.test", "https://primal.net:8443", "http://primal.net", "https://unknown.example", "https://nostrudel.ninja", "https://nostr.watch", "https://njump.me"] {
            XCTAssertEqual(BrowserSiteDefaults.forOrigin(origin), .unknown)
        }
    }

}
