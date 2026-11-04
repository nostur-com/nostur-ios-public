import Foundation

/// Display labels only: recognizing a kind never grants signing permission.
/// Source: https://github.com/nostr-protocol/nips#event-kinds
enum BrowserEventDescription {
    static func name(for kind: Int) -> String {
        switch kind {
        case 0: return String(localized: "Profile update")
        case 1: return String(localized: "Public post")
        case 3: return String(localized: "Following list update")
        case 4: return String(localized: "Private message (legacy)")
        case 5: return String(localized: "Event deletion request")
        case 6, 16: return String(localized: "Repost")
        case 7: return String(localized: "Reaction")
        case 8: return String(localized: "Badge award")
        case 9, 42, 1311: return String(localized: "Chat message")
        case 11: return String(localized: "Forum thread")
        case 13: return String(localized: "Private message seal")
        case 14: return String(localized: "Private message")
        case 15: return String(localized: "Private file message")
        case 17: return String(localized: "Website reaction")
        case 20: return String(localized: "Photo post")
        case 21, 34235: return String(localized: "Video post")
        case 22, 34236: return String(localized: "Short video post")
        case 24: return String(localized: "Public message")
        case 40: return String(localized: "Chat channel creation")
        case 41: return String(localized: "Chat channel update")
        case 43: return String(localized: "Hide chat message")
        case 44: return String(localized: "Mute chat participant")
        case 54: return String(localized: "Podcast episode")
        case 62: return String(localized: "Account content removal request")
        case 64: return String(localized: "Chess game")
        case 78, 30078: return String(localized: "App-specific data")
        case 1018: return String(localized: "Poll vote")
        case 1059, 21059: return String(localized: "Private message envelope")
        case 1063: return String(localized: "File information")
        case 1068: return String(localized: "Poll creation")
        case 1111: return String(localized: "Comment")
        case 1222, 1244: return String(localized: "Voice message")
        case 1234, 30024, 31234: return String(localized: "Draft content")
        case 1337: return String(localized: "Code snippet")
        case 1617: return String(localized: "Code patch")
        case 1618, 1619: return String(localized: "Pull request")
        case 1621: return String(localized: "Issue report")
        case 1984: return String(localized: "Content or account report")
        case 1985: return String(localized: "Content label")
        case 2003: return String(localized: "Torrent listing")
        case 2004: return String(localized: "Torrent comment")
        case 4550: return String(localized: "Community post approval")
        case 7374, 7375: return String(localized: "Cashu wallet tokens")
        case 7376: return String(localized: "Cashu wallet history")
        case 8000: return String(localized: "Relay member addition")
        case 8001: return String(localized: "Relay member removal")
        case 9000...9030: return String(localized: "Group administration")
        case 9041: return String(localized: "Zap goal")
        case 9321: return String(localized: "Cashu payment")
        case 9734: return String(localized: "Zap request")
        case 9735: return String(localized: "Zap receipt")
        case 9802: return String(localized: "Text highlight")
        case 10000, 30007: return String(localized: "Mute list update")
        case 10001: return String(localized: "Pinned posts update")
        case 10002, 30002: return String(localized: "Relay list update")
        case 10003, 30003: return String(localized: "Bookmarks update")
        case 10004: return String(localized: "Community subscriptions update")
        case 10005: return String(localized: "Chat subscriptions update")
        case 10006: return String(localized: "Blocked relays update")
        case 10007: return String(localized: "Search relays update")
        case 10008, 30008: return String(localized: "Profile badges update")
        case 10009: return String(localized: "Group memberships update")
        case 10011: return String(localized: "Linked identities update")
        case 10012: return String(localized: "Favorite relays update")
        case 10013: return String(localized: "Private content relays update")
        case 10015, 30015: return String(localized: "Interests update")
        case 10019, 38000: return String(localized: "Cashu mint recommendation")
        case 10020: return String(localized: "Media following list update")
        case 10021, 30000: return String(localized: "Following groups update")
        case 10030, 30030: return String(localized: "Emoji collection update")
        case 10040: return String(localized: "Trusted services update")
        case 10050: return String(localized: "Private message relays update")
        case 10063, 10096: return String(localized: "Media servers update")
        case 10133: return String(localized: "Payment destinations update")
        case 10166, 30166: return String(localized: "Relay discovery information")
        case 10312: return String(localized: "Room presence")
        case 13194: return String(localized: "Wallet information")
        case 13534: return String(localized: "Relay membership list")
        case 17375: return String(localized: "Cashu wallet configuration")
        case 22242: return String(localized: "Relay authentication")
        case 23194: return String(localized: "Wallet command")
        case 23195: return String(localized: "Wallet response")
        case 24133: return String(localized: "Remote signer communication")
        case 24242: return String(localized: "Media storage authorization")
        case 27235: return String(localized: "Website login or upload authorization")
        case 28934: return String(localized: "Relay join request")
        case 28935: return String(localized: "Relay invitation request")
        case 28936: return String(localized: "Relay leave request")
        case 30004: return String(localized: "Content collection update")
        case 30005: return String(localized: "Video collection update")
        case 30006: return String(localized: "Photo collection update")
        case 30009: return String(localized: "Badge definition")
        case 30017: return String(localized: "Marketplace shop update")
        case 30018, 30020, 30402: return String(localized: "Marketplace listing")
        case 30023: return String(localized: "Long-form article")
        case 30063: return String(localized: "Software release collection")
        case 30267: return String(localized: "App collection update")
        case 30311: return String(localized: "Live event announcement")
        case 30312: return String(localized: "Interactive room")
        case 30313: return String(localized: "Conference event")
        case 30315: return String(localized: "Account status update")
        case 30382...30384: return String(localized: "Trust assertion")
        case 30403: return String(localized: "Draft marketplace listing")
        case 30617, 30618: return String(localized: "Code repository update")
        case 30818: return String(localized: "Wiki article")
        case 30819: return String(localized: "Wiki redirect")
        case 31922, 31923: return String(localized: "Calendar event")
        case 31924: return String(localized: "Calendar update")
        case 31925: return String(localized: "Calendar attendance response")
        case 31989: return String(localized: "App recommendation")
        case 31990: return String(localized: "App handler information")
        case 32267: return String(localized: "Software application information")
        case 33534: return String(localized: "Relay role definition")
        case 34550: return String(localized: "Community definition")
        case 38172, 38173: return String(localized: "Payment mint announcement")
        default: return String(localized: "Unrecognized event type")
        }
    }

    static func blockedMessage(for event: BrowserUnsignedEvent, reason: String? = nil) -> String {
        let name = name(for: event.kind)
        let kind = String(event.kind) // Protocol identifiers must not acquire locale grouping separators.
        var message = String(localized: "Blocked: \(name) (kind \(kind)).")
        switch event.kind {
        case 22242:
            message += " " + String(localized: "The app wants to sign in to a Nostr relay using your account.")
            if let relay = relayAddress(in: event.tags) {
                message += " " + String(localized: "Requested relay: \(relay).")
            }
        case 78, 30078:
            message += " " + String(localized: "Used for app preferences or custom service requests. The kind alone does not identify the requested action.")
        case 23194:
            message += " " + String(localized: "Wallet commands can request payments or access wallet information.")
        default:
            break
        }
        if let reason { message += " " + reason }
        return message
    }

    private static func relayAddress(in tags: [[String]]) -> String? {
        let relays = tags.filter { $0.first == "relay" }
        guard relays.count == 1, relays[0].count == 2,
              let url = URL(string: relays[0][1]),
              ["wss", "ws"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              let host = url.host, !host.isEmpty, host.count <= 253,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-:[]".contains($0)) }) else { return nil }
        // Omit paths, queries and fragments: these may contain private tokens.
        return "\(url.scheme!.lowercased())://\(host)" + (url.port.map { ":\($0)" } ?? "")
    }
}
