import Foundation

/// The web page supplies only an unsigned event. Identity, event ID and signature
/// are always produced by Nostur, never taken from JavaScript.
struct BrowserUnsignedEvent: Codable, Equatable, Sendable {
    let created_at: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
}

struct BrowserRelaySetting: Sendable {
    let url: String
    let auth: Bool
}

struct BrowserSigningApproval: Sendable {
    let event: BrowserUnsignedEvent
    let accountPubkey: String
    let origin: String
    let approvedAt: Int64
    fileprivate init(event: BrowserUnsignedEvent, accountPubkey: String, origin: String, approvedAt: Int64) {
        self.event = event
        self.accountPubkey = accountPubkey
        self.origin = origin
        self.approvedAt = approvedAt
    }
}

enum BrowserSigningPolicy {
    static func origin(scheme: String, host: String, port: Int) -> String? {
        guard scheme.lowercased() == "https", !host.isEmpty, (0...65535).contains(port) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.lowercased()
        components.port = port == 0 || port == 443 ? nil : port
        return origin(components.url)
    }
    static func origin(_ url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return "https://" + host + ((url.port == nil || url.port == 443) ? "" : ":\(url.port!)")
    }

    static func socialDefault(_ origin: String) -> Bool {
        BrowserSiteDefaults.forOrigin(origin).social
    }

    // Protect account-wide replacement state and known sensitive protocols, rather
    // than requiring every new game or public app event to join an allowlist.
    static func requiresExtraPermission(_ kind: Int) -> Bool {
        (10000..<20000).contains(kind) ||
        [0, 3, 5, 62, 30000, 30002, 30003, 30004, 30005, 30006, 30007,
         30008, 30015, 30030, 30315].contains(kind)
    }

    static let nwcKinds: Set<Int> = [13194, 23194, 23195, 23196, 23197]
    static func isDeletion(_ kind: Int) -> Bool { kind == 5 || kind == 62 }
    static func isAccountChange(_ kind: Int) -> Bool {
        requiresExtraPermission(kind) && !isDeletion(kind) && !nwcKinds.contains(kind) && !isRestrictedProtocol(kind)
    }

    static func isRestrictedProtocol(_ kind: Int) -> Bool {
        [4, 13, 14, 15, 1059, 21059, 7374, 7375, 7376, 9321,
         17375, 22242, 23194, 23195, 23196, 23197, 24133, 24242, 27235, 38000, 38172, 38173].contains(kind) ||
        (8000...8001).contains(kind) || (9000...9030).contains(kind)
    }

    static func isAppAction(_ kind: Int) -> Bool {
        (0...65535).contains(kind) && !requiresExtraPermission(kind) && !isRestrictedProtocol(kind)
    }

    // Explicit native user grants may enable recognized public/account actions.
    // Private messages, remote-signer commands and unknown kinds cannot be
    // granted. NWC events can be enabled separately from account changes. HTTP/Blossom grants still pass all protocol-specific checks.
    static func canGrant(_ kind: Int) -> Bool {
        nwcKinds.contains(kind) || [0, 1, 3, 5, 6, 7, 8, 9, 11, 16, 17, 20, 21, 22, 24, 40, 41, 42, 43, 44, 64, 78,
         1018, 1063, 1068, 1111, 1222, 1244, 1311, 1337, 1617, 1618, 1619, 1621, 1984, 1985,
         2003, 2004, 9041, 9734, 9802, 24242, 27235, 10000, 10001, 10002, 10003, 10004, 10005, 10006, 10007,
         10008, 10009, 10012, 10015, 10020, 10021, 10030, 10050, 10063, 10096, 30000, 30002,
         30003, 30004, 30005, 30006, 30007, 30008, 30009, 30015, 30017, 30018, 30020, 30023,
         30024, 30030, 30311, 30312, 30313, 30315, 30402, 30403, 30617, 30618, 30818, 30819,
         31922, 31923, 31924, 31925, 31989, 31990, 32267, 34235, 34236, 34550].contains(kind)
    }

    static func approval(for event: BrowserUnsignedEvent, accountPubkey: String, origin: String,
                         connected: Bool, social: Bool, websiteAuth: Bool, uploads: Bool,
                         relaySettings: [BrowserRelaySetting], accountChanges: Bool = false, deletions: Bool = false, wallet: Bool = false, allowedKinds: Set<Int> = [], now: Int64 = Int64(Date().timeIntervalSince1970)) -> BrowserSigningApproval? {
        guard connected, BrowserSignedEvent.isHex(accountPubkey, count: 64),
              rejection(for: event, origin: origin, social: social, websiteAuth: websiteAuth,
                        uploads: uploads, relaySettings: relaySettings, accountChanges: accountChanges, deletions: deletions, wallet: wallet, allowedKinds: allowedKinds, now: now) == nil else { return nil }
        return BrowserSigningApproval(event: event, accountPubkey: accountPubkey, origin: origin, approvedAt: now)
    }

    static func rejection(for event: BrowserUnsignedEvent, origin: String,
                          social: Bool, websiteAuth: Bool = false, uploads: Bool = false, relaySettings: [BrowserRelaySetting] = [], accountChanges: Bool = false, deletions: Bool = false, wallet: Bool = false, allowedKinds: Set<Int> = [],
                          now: Int64 = Int64(Date().timeIntervalSince1970)) -> String? {
        func blocked(_ reason: String? = nil) -> String {
            BrowserEventDescription.blockedMessage(for: event, reason: reason)
        }
        guard Self.origin(URL(string: origin)) == origin else { return blocked(String(localized: "A secure website is required.")) }
        guard (0...65535).contains(event.kind), event.content.utf8.count <= 65536,
              event.tags.count <= 256,
              event.tags.allSatisfy({ !$0.isEmpty && $0.count <= 16 && $0.allSatisfy { $0.utf8.count <= 4096 } }),
              event.created_at >= now - 300, event.created_at <= now + 60 else {
            return blocked(String(localized: "Invalid, oversized, or expired signing request."))
        }
        // Never allow websites to delegate authority using NIP-26 tags.
        guard !event.tags.contains(where: { $0.first == "delegation" }) else { return blocked(String(localized: "Delegation is blocked.")) }

        if allowedKinds.contains(event.kind), canGrant(event.kind), ![24242, 27235].contains(event.kind) { return nil }

        // General app data is permitted for connected sites. The broker checks
        // connection, native account and document scope before and after signing.
        if event.kind == 30078 { return nil }

        if event.kind == 22242 {
            let relays = event.tags.filter { $0.first == "relay" }
            let challenges = event.tags.filter { $0.first == "challenge" }
            guard event.content.isEmpty, event.created_at >= now - 60,
                  relays.count == 1, relays[0].count == 2,
                  challenges.count == 1, challenges[0].count == 2, !challenges[0][1].isEmpty,
                  let relay = relayIdentity(relays[0][1]) else {
                return blocked(String(localized: "Relay authentication requires a fresh, empty event with one relay and one challenge."))
            }
            let matching = relaySettings.filter { relayIdentity($0.url) == relay }
            guard !matching.isEmpty, matching.allSatisfy(\.auth) else {
                return blocked(String(localized: "Enable authentication for this relay in Nostur's relay settings."))
            }
            return nil
        }

        if event.kind == 27235 {
            let urls = event.tags.filter { $0.first == "u" }
            let methods = event.tags.filter { $0.first == "method" }
            guard urls.count == 1, urls[0].count == 2,
                  methods.count == 1, methods[0].count == 2,
                  ["GET", "HEAD", "POST", "PUT", "PATCH"].contains(methods[0][1]),
                  event.content.isEmpty, event.created_at >= now - 60,
                  let url = URL(string: urls[0][1]), url.fragment == nil,
                  let target = Self.origin(url) else {
                return blocked(String(localized: "Invalid website login or upload authorization."))
            }
            let payloads = event.tags.filter { $0.first == "payload" }
            guard payloads.isEmpty || (payloads.count == 1 && payloads[0].count == 2 && BrowserSignedEvent.isHex(payloads[0][1], count: 64)) else {
                return blocked(String(localized: "Invalid request-body hash."))
            }
            if (websiteAuth || allowedKinds.contains(27235)) && (target == origin || BrowserSiteDefaults.isHomepageApp(origin)) { return nil }
            return blocked(String(localized: "Website account access is disabled, or this app is not allowed to authorize another HTTPS service."))
        }

        // Blossom upload tokens must name a single file and expire shortly.
        // Listing, downloading private files and deleting uploads remain blocked.
        if event.kind == 24242 {
            guard uploads || allowedKinds.contains(24242) else { return blocked(String(localized: "Media upload authorization is disabled in website controls.")) }
            let actions = event.tags.filter { $0.first == "t" }
            let hashes = event.tags.filter { $0.first == "x" }
            let expiry = event.tags.filter { $0.first == "expiration" }
            guard actions == [["t", "upload"]], hashes.count == 1, hashes[0].count == 2,
                  hashes[0][1].count == 64, hashes[0][1].allSatisfy({ $0.isHexDigit && $0.isASCII }),
                  expiry.count == 1, expiry[0].count == 2, let expiration = Int64(expiry[0][1]),
                  expiration > now, expiration <= now + 600 else {
                return blocked(String(localized: "Only short-lived, file-specific upload authorization is allowed."))
            }
            return nil
        }
        if nwcKinds.contains(event.kind) {
            return wallet ? nil : blocked(String(localized: "Wallet actions are disabled in website controls."))
        }
        if isAccountChange(event.kind), accountChanges { return nil }
        if isDeletion(event.kind), deletions { return nil }
        if requiresExtraPermission(event.kind) {
            return blocked(String(localized: "This action can change shared account data or remove content. Allow it explicitly if you trust this app."))
        }
        if isRestrictedProtocol(event.kind) { return blocked() }
        if social { return nil }
        return blocked(String(localized: "App actions are disabled in website controls."))
    }

    /// Normalize scheme, host, default ports and the root slash only. Preserve
    /// path/query case and values: sharing a host does not imply the same relay.
    static func relayIdentity(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), ["wss", "ws"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil else { return nil }
        components.scheme = scheme
        components.host = host
        if (scheme == "wss" && components.port == 443) || (scheme == "ws" && components.port == 80) { components.port = nil }
        if components.percentEncodedPath == "/" { components.percentEncodedPath = "" }
        guard components.url != nil else { return nil }
        return components.string
    }
}
