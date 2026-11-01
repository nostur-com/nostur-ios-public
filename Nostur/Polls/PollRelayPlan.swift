import Foundation

/// Which relays a poll advertises, and which relays a viewer may contact for results.
/// Relay selection is pure so it can be tested without Core Data or the network.
struct PollRelayPlan: Equatable, Sendable {
    struct Input: Equatable, Sendable {
        var announcedRead: [String] = []
        var announcedWrite: [String] = []
        var configuredRead: [String] = []
        var configuredWrite: [String] = []
        var authRelays: [String] = []
        var disabled: [String] = []
        var eventRelays: [String] = []
        var outboxEnabled = false
        var followsAuthor = false
        var isOwnPoll = false
        var lockRelay: String? = nil
    }

    struct Query: Equatable, Sendable {
        var relays: [String]
        var more: [String]
    }

    static let maximumAdvertised = 8
    static let maximumForeign = 8

    /// Public `wss` relays other people can be asked to write to.
    static func isPublicRelay(_ url: String) -> Bool {
        guard let parts = URLComponents(string: url), parts.scheme == "wss",
              let host = parts.host?.lowercased(), !host.isEmpty,
              host != "localhost", host != "127.0.0.1", host != "::1",
              !host.hasPrefix("127."), !host.hasSuffix(".local") else { return false }
        return true
    }

    /// Relays written into a new poll. Publishing still uses the normal write path.
    /// Prefer announced read relays (kind 10002, marker absent or `read`) that this account also reads.
    static func advertised(_ input: Input) -> [String] {
        if let lockRelay = input.lockRelay {
            return Array(NostrPoll.relayURLs([lockRelay]).prefix(1))
        }
        let announced = advertisable(input.announcedRead, input)
        let configured = advertisable(input.configuredRead, input)
        let configuredSet = Set(configured)
        let overlap = announced.filter { configuredSet.contains($0) }
        if !overlap.isEmpty { return Array(overlap.prefix(maximumAdvertised)) }
        if !announced.isEmpty { return Array(announced.prefix(maximumAdvertised)) }
        return Array(configured.prefix(maximumAdvertised))
    }

    /// Read relays, plus outbox write relays when that routing is on and the author is trusted.
    /// Event relays are queried for our own polls and people we follow. Otherwise only the ones
    /// we already use are queried; the rest stay in `more` until the viewer asks.
    static func query(_ input: Input, includeMore: Bool = false) -> Query {
        let disabled = Set(NostrPoll.relayURLs(input.disabled))
        let auth = Set(NostrPoll.relayURLs(input.authRelays))
        let ownRead = usable(input.configuredRead, disabled: disabled)
        let own = Set(ownRead + usable(input.configuredWrite, disabled: disabled))
        var relays: [String] = []
        func append(_ urls: [String]) {
            for url in urls where !relays.contains(url) { relays.append(url) }
        }
        append(ownRead)

        let trusted = input.followsAuthor || input.isOwnPoll
        if input.outboxEnabled && trusted {
            append(usable(input.announcedWrite, disabled: disabled).filter { own.contains($0) || (isPublicRelay($0) && !auth.contains($0)) })
        }

        let event = usable(input.eventRelays, disabled: disabled)
            .filter { own.contains($0) || (isPublicRelay($0) && !auth.contains($0)) }
        var more: [String] = []
        if trusted {
            append(event)
        } else {
            for url in event {
                if own.contains(url) { append([url]) }
                else if !more.contains(url) { more.append(url) }
            }
        }

        var kept: [String] = []
        var overflow: [String] = []
        var foreign = 0
        for url in relays {
            if own.contains(url) || foreign < maximumForeign {
                if !own.contains(url) { foreign += 1 }
                kept.append(url)
            } else {
                overflow.append(url)
            }
        }
        more = overflow + more.filter { !overflow.contains($0) && !kept.contains($0) }

        guard includeMore else { return Query(relays: kept, more: more) }
        var added = 0
        var remain: [String] = []
        for url in more {
            if added < maximumForeign && !kept.contains(url) {
                kept.append(url)
                added += 1
            } else if !kept.contains(url) {
                remain.append(url)
            }
        }
        return Query(relays: kept, more: remain)
    }

    private static func advertisable(_ urls: [String], _ input: Input) -> [String] {
        let disabled = Set(NostrPoll.relayURLs(input.disabled))
        let auth = Set(NostrPoll.relayURLs(input.authRelays))
        return NostrPoll.relayURLs(urls).filter { isPublicRelay($0) && !disabled.contains($0) && !auth.contains($0) }
    }

    private static func usable(_ urls: [String], disabled: Set<String>) -> [String] {
        NostrPoll.relayURLs(urls).filter { !disabled.contains($0) }
    }
}

/// Live relay lists for the pure plan. Call on the main actor; reads stay on the view context.
enum PollRelayContext {
    static func advertisedRelays(accountPubkey: String, lockURL: String?) -> [String] {
        if let lockURL, !lockURL.isEmpty {
            return PollRelayPlan.advertised(PollRelayPlan.Input(lockRelay: lockURL))
        }
        let relays = accountRelays(accountPubkey)
        let input = PollRelayPlan.Input(
            announcedRead: announced(accountPubkey, marker: "read"),
            configuredRead: relays.read,
            authRelays: relays.auth,
            disabled: DisabledRelaysStore.all()
        )
        return filterDisabled(PollRelayPlan.advertised(input))
    }

    static func query(accountPubkey: String, authorPubkey: String, eventRelays: [String], includeMore: Bool) -> PollRelayPlan.Query {
        let relays = accountRelays(accountPubkey)
        let own = !authorPubkey.isEmpty && authorPubkey == accountPubkey
        let follows = own || isFollowing(authorPubkey)
        let outbox = SettingsStore.shared.enableOutboxRelays
        let input = PollRelayPlan.Input(
            announcedWrite: (outbox && follows) ? announced(authorPubkey, marker: "write") : [],
            configuredRead: relays.read,
            configuredWrite: relays.write,
            authRelays: relays.auth,
            disabled: DisabledRelaysStore.all(),
            eventRelays: eventRelays,
            outboxEnabled: outbox,
            followsAuthor: follows,
            isOwnPoll: own
        )
        let plan = PollRelayPlan.query(input, includeMore: includeMore)
        return PollRelayPlan.Query(relays: filterDisabled(plan.relays), more: filterDisabled(plan.more))
    }

    private static func filterDisabled(_ urls: [String]) -> [String] {
        urls.filter { !DisabledRelaysStore.isDisabled($0) }
    }

    private static func accountRelays(_ accountPubkey: String) -> (read: [String], write: [String], auth: [String]) {
        let relays = CloudRelay.fetchAll(context: context()).filter { !$0.excludedPubkeys.contains(accountPubkey) }
        return (
            relays.filter(\.read).compactMap(\.url_),
            relays.filter(\.write).compactMap(\.url_),
            relays.filter(\.auth).compactMap(\.url_)
        )
    }

    /// Kind 10002 `r` tags. A missing marker means the relay is used for both reading and writing.
    private static func announced(_ pubkey: String, marker: String) -> [String] {
        guard !pubkey.isEmpty,
              let event = Event.fetchReplacableEvent(10002, pubkey: pubkey, context: context()) else { return [] }
        return event.fastTags.compactMap { tag in
            guard tag.0 == "r", !tag.1.isEmpty, tag.2 == nil || tag.2 == marker else { return nil }
            return tag.1
        }
    }
}
