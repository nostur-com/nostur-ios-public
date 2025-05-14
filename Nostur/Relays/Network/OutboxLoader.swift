//
//  OutboxLoader.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/07/2024.
//

import Foundation
import CoreData
import NostrEssentials
import Combine

public class OutboxLoader {
    
    private let pubkey: String // Account
    private let follows: Set<String> // Follows
    private let context: NSManagedObjectContext

    private var mostRecentKind10002At: Int?
    
    private var cp: ConnectionPool
    private var backlog: Backlog
    private var subscriptions: Set<AnyCancellable> = []
    
    init(pubkey: String, follows: Set<String> = [], cp: ConnectionPool) {
        self.pubkey = pubkey
        self.follows = follows
        self.cp = cp
        self.backlog = Backlog(timeout: 60, auto: true)
        self.context = bg()
        
        fetchKind1002AfterNewFollowListener()
        self.load()
    }
    
    private func fetchKind1002AfterNewFollowListener() {
        receiveNotification(.followingAdded)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let pubkey = notification.object as! String
                self.fetchKind10002(forPubkey: pubkey)
            }
            .store(in: &subscriptions)
    }

    public func load() {
        // TODO: Skip if outbox disabled, track didLoad, run on toggle on + !didLoad
        
        // Load from DB, then fetch more
        
        self.loadKind10002sFromDb { kind10002s in
            
            self.mostRecentKind10002At = kind10002s.sorted(by: { $0.created_at > $1.created_at }).first?.created_at
            self.cp.queue.async(flags: .barrier) { [weak self] in
                self?.cp.setPreferredRelays(using: kind10002s)
            }
            
#if DEBUG
            L.sockets.debug("📤📤 Outbox: loaded \(kind10002s.count) from db")
#endif
            self.fetchMoreKind10002sFromRelays()
        }
    }
    
    private func loadKind10002sFromDb(_ completion: (([NostrEssentials.Event]) -> Void)? = nil) {
        context.perform { [weak self] in
            guard let self else { return }
            
            let kind10002s: [NostrEssentials.Event] = Event.fetchReplacableEvents(10002, pubkeys: self.follows, context: context)
                .map { event in
                    return event.toNostrEssentialsEvent()
                }
            completion?(kind10002s)
        }
    }
    
    private func fetchMoreKind10002sFromRelays() {
        let task = ReqTask(
            debounceTime: 3.0,
            prefix: "OUTBOX1-",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                      
                let follows = self.follows.count <= 2000 ? self.follows : Set(self.follows.shuffled().prefix(2000))
                        
                guard let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   subscriptionId: taskId,
                                   filters: [Filters(authors: follows, kinds: [10002], since: self.mostRecentKind10002At)]
                    ).json()
                else { return }
                
#if DEBUG
                L.sockets.debug("📤📤 Outbox: Fetching contact relay info for \(self.follows) follows -[LOG]-")
#endif
                req(cm)
            },
            processResponseCommand: { [weak self] taskId, _, _ in
                guard let self else { return }
                
                self.loadKind10002sFromDb { kind10002s in
                    
                    self.mostRecentKind10002At = kind10002s.sorted(by: { $0.created_at > $1.created_at }).first?.created_at
                    self.cp.queue.async(flags: .barrier) { [weak self] in
                        self?.cp.setPreferredRelays(using: kind10002s)
                    }
                    
#if DEBUG
                    L.sockets.debug("📤📤 Outbox: loaded \(kind10002s.count) from db")
#endif
                }
            },
            timeoutCommand: { taskId in
#if DEBUG
                L.sockets.debug("📤📤 Outbox: timeout or no new kind 10002s")
#endif
            })

        backlog.add(task)
        task.fetch()
    }
    
    private func fetchKind10002(forPubkey pubkey: String) {
        let task = ReqTask(
            debounceTime: 3.0,
            prefix: "OUTBOX2-",
            reqCommand: { taskId in
                guard let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   subscriptionId: taskId,
                                   filters: [Filters(authors: [pubkey], kinds: [10002])]
                    ).json()
                else { return }

#if DEBUG
                L.sockets.debug("📤📤 Outbox: Fetching contact relay info for \(pubkey)")
#endif
                req(cm)
            },
            processResponseCommand: { [weak self] taskId, _, _ in
                guard let self else { return }
                
                self.loadKind10002sFromDb { kind10002s in

                    self.cp.queue.async(flags: .barrier) { [weak self] in
                        self?.cp.reloadPreferredRelays(kind10002s: kind10002s)
                    }
                    
#if DEBUG
                    L.sockets.debug("📤📤 Outbox: reloading for \(pubkey)")
#endif
                }
            },
            timeoutCommand: { taskId in
#if DEBUG
                L.sockets.debug("📤📤 Outbox: timeout or no kind 10002 for \(pubkey)")
#endif
            })

        backlog.add(task)
        task.fetch()
    }
}

// Takes a pubkey and tries to return a usable relay hint
public func resolveRelayHint(forPubkey pubkey: String, receivedFromRelays: Set<String> = []) -> Set<String> {
    // Possible sources:
    // - Event "Received from:" Event.relays (passed in as receivedFromRelays).
    // - Actual received connection stats: ConnectionPool.shared.connectionStats
    // - Pubkey's kind 10002 write relays
    
    // PREFER: Write relay from pubkey's kind 10002 + actual received from in (some) Event.relays
    
    let kind10002: Event? = Event.fetchReplacableEvent(10002, pubkey: pubkey, context: context())
    
    let writeRelays: Set<String> = Set( kind10002?.fastTags.filter({ relay in
        relay.0 == "r" && (relay.2 == nil || relay.2 == "write")
    }).map { normalizeRelayUrl($0.1) } ?? [] )
            
    
    if writeRelays.isEmpty { // Write from kind:10002 is required mininum, else don't continue
        return []
    }
    
    // Only CanonicalRelayUrls where pubkey is in RelayConnectionStats.receivedPubkeys
    let connectionStatsRelayUrls: Set<String> = Set( ConnectionPool.shared.connectionStats.filter { _ , relayStats in
        return relayStats.receivedPubkeys.contains(pubkey)
    }.keys.map { normalizeRelayUrl($0) } )
    
    // Relays to always remove
    let authRelays = Set(ConnectionPool.shared.connections.filter { $0.value.relayData.auth }.keys.map { String($0) })
    
    // find the relay with the most matches in the sets writeRelays, actualReceivedRelayUrls and receivedFromRelays:
    
    // WRITE + STATS + RECEIVED
    let primaryMatches: Set<String> = writeRelays
        .intersection(connectionStatsRelayUrls)
        .intersection(receivedFromRelays)
        .subtracting(authRelays)
    
    if !primaryMatches.isEmpty {
        return primaryMatches.filter {  // don't inculude localhost / 127.0.x.x / ws:// (non-wss)
            !$0.contains("/localhost") && !$0.contains("ws:/") && !$0.contains("s:/127.0") && $0 != "local" && $0 != "iCloud"
        }
    }
    
    // WRITE + RECEIVED
    let secondaryMatches: Set<String> = writeRelays
        .intersection(receivedFromRelays)
        .subtracting(authRelays)
    
    if !secondaryMatches.isEmpty {
        return secondaryMatches.filter {  // don't inculude localhost / 127.0.x.x / ws:// (non-wss)
            !$0.contains("/localhost") && !$0.contains("ws:/") && !$0.contains("s:/127.0") && $0 != "local" && $0 != "iCloud"
        }
    }
    
    // WRITE + STATS
    let moreMatches: Set<String> = writeRelays
        .intersection(connectionStatsRelayUrls)
        .subtracting(authRelays)
    
    if !moreMatches.isEmpty {
        return moreMatches.filter {  // don't inculude localhost / 127.0.x.x / ws:// (non-wss)
            !$0.contains("/localhost") && !$0.contains("ws:/") && !$0.contains("s:/127.0") && $0 != "local" && $0 != "iCloud"
        }
    }
    
    // WRITE?
    if !writeRelays.isEmpty {
        return writeRelays.filter {  // don't inculude localhost / 127.0.x.x / ws:// (non-wss)
            !$0.contains("/localhost") && !$0.contains("ws:/") && !$0.contains("s:/127.0") && $0 != "local" && $0 != "iCloud"
        }
    }
    
    return []
}


extension Event {
    func toNostrEssentialsEvent() -> NostrEssentials.Event {
        return NostrEssentials.Event(
            pubkey: self.pubkey,
            content: self.content ?? "",
            kind: Int(self.kind),
            created_at: Int(self.created_at),
            id: self.id,
            tags: tagsSerializedToTags(self.tagsSerialized),
            sig: self.sig ?? "")
    }
}

extension NEvent {
    func toNostrEssentialsEvent() -> NostrEssentials.Event {
        return NostrEssentials.Event(
            pubkey: self.publicKey,
            content: self.content,
            kind: self.kind.id,
            created_at: self.createdAt.timestamp,
            id: self.id,
            tags: self.tags.map { Tag($0.tag) },
            sig: self.signature)
    }
}

// From Nostur .tagsSerialized to [NostrEssentials.Tag]
func tagsSerializedToTags(_ tagsSerialized: String?) -> [Tag] {
    guard let tagsSerialized = tagsSerialized else { return [] }
    guard let jsonData = tagsSerialized.data(using: .utf8) else { return [] }
    
    guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String]] else {
        return []
    }
    
    return jsonArray.map { stringArray in
        return Tag(stringArray)
    }
}

extension Filters {
    
    // Normally a Filters REQ is sent to a relay, but for outbox we send the same req to different relays with different pubkeys
    // to get only events from those pubkeys. But if the REQ also contains hashtags ("t") we need to remove that
    func withoutHashtags() -> Filters {
        if self.tagFilter?.tag == "t" {
            return Filters(
                ids: self.ids,
                authors: self.authors,
                kinds: self.kinds,
                since: self.since,
                until: self.until,
                limit: self.limit
            )
        }
        return self
    }
    
    var hasHashtags: Bool {
        return self.tagFilter?.tag == "t"
    }
}


// Some clients put wrong relays in kind 10002, or don't explain to users what to put in there
// Probably because its still early and people dont know how to use outbox yet
// So to detect useless kind 10002s we have some hardcoded relays, if these are found we can assume
// the kind 10002 is incorrectly configured and just ignore it
// these are relays that others are not supposed to read from, but announced in the kind 10002 as if it should
// We match these relays by "starts with"
let DETECT_MISCONFIGURED_KIND10002_HELPER_LIST: Set<String> = [
    "ws://127.0.0.1",
    "ws://localhost",
    "wss://filter.nostr.wine", // is paid
    "wss://welcome.nostr.wine", // is special feed relay
    "wss://nostr.mutinywallet.com", // is write only relay (blastr)
    "wss://feeds.nostr.band", // special feeds
    "wss://search.nos.today",
    "wss://relay.getalby.com" // only for NWC connections
]

func removeMisconfiguredKind10002s(_ kind10002s: [NostrEssentials.Event]) -> [NostrEssentials.Event] {
    
    
    return kind10002s.filter { kind10002 in
        
        // Relays the user says they are writing to
        let writeRelays = kind10002.tags.filter { tag in
            tag.type == "r" && (tag.tag.count == 2 || (tag.tag.count == 3 && tag.tag[2] == "write"))
        }
        
        // Check if one the write relays can't be written to or can't be used for others to read from (DETECT_MISCONFIGURED_KIND10002_HELPER_LIST)
        // Then we know this kind 10002 is garbage and we can ignore it
        for writeRelay in writeRelays {
            guard let relay = writeRelay.value?.lowercased() else { continue }
            for detect in DETECT_MISCONFIGURED_KIND10002_HELPER_LIST {
                if relay.starts(with: detect) {
                    return false
                }
            }
        }
        
        return true
    }
}
