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

struct OutboxRefreshPolicy {
    static let batchSize = 150
    static let deferredDelay: TimeInterval = 20
    static let auditInterval: TimeInterval = 24 * 60 * 60
    static let incrementalOverlap: TimeInterval = 60 * 60

    static func missingAuthors(allAuthors: Set<String>, storedAuthors: Set<String>) -> Set<String> {
        allAuthors.subtracting(storedAuthors)
    }

    static func batches(from authors: Set<String>, size: Int = batchSize) -> [Set<String>] {
        guard size > 0, !authors.isEmpty else { return [] }
        let sorted = authors.sorted()
        return stride(from: 0, to: sorted.count, by: size).map { start in
            Set(sorted[start..<min(start + size, sorted.count)])
        }
    }

    static func shouldAudit(lastAttempt: Date?, now: Date = .now) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= auditInterval
    }
}

public class OutboxLoader {
    
    private let pubkey: String // Account
    private var follows: Set<String> // Follows
    private var contactFeedPubkeys: Set<String> = [] // pubkeys from custom contact feeds with .useOutbox enabled
    private let context: NSManagedObjectContext

    private var cp: ConnectionPool
    private var backlog: Backlog
    private var subscriptions: Set<AnyCancellable> = []
    private var deferredMaintenanceWorkItem: DispatchWorkItem?
    private var isAppInBackground = false

    private var auditDefaultsKey: String { "outbox_kind10002_audit_\(pubkey)" }
    private var refreshDefaultsKey: String { "outbox_kind10002_refresh_\(pubkey)" }
    
    init(pubkey: String, follows: Set<String> = [], cp: ConnectionPool) {
        self.pubkey = pubkey
        self.follows = follows
        self.cp = cp
        self.backlog = Backlog(timeout: 9, auto: true, backlogDebugName: "OutboxLoader")
        self.context = bg()
        
        listenForFollowChanges()
        listenForForegrounding()
        self.load()
    }

    deinit {
        deferredMaintenanceWorkItem?.cancel()
    }

    private func listenForFollowChanges() {
        receiveNotification(.followsChanged)
            .sink { [weak self] notification in
                guard let self, let updatedFollows = notification.object as? Set<String> else { return }
                let added = updatedFollows.subtracting(self.follows)
                self.follows = updatedFollows
                self.reloadPreferredRelaysFromDb()
                guard !added.isEmpty else { return }
                self.fetchBatches(
                    OutboxRefreshPolicy.batches(from: added),
                    since: nil,
                    prefix: "OUTBOX-NEW-"
                )
            }
            .store(in: &subscriptions)
    }

    private func listenForForegrounding() {
        receiveNotification(.scenePhaseActive)
            .sink { [weak self] _ in
                self?.isAppInBackground = false
                self?.scheduleDeferredMaintenance()
            }
            .store(in: &subscriptions)

        receiveNotification(.scenePhaseBackground)
            .sink { [weak self] _ in
                self?.isAppInBackground = true
                self?.deferredMaintenanceWorkItem?.cancel()
            }
            .store(in: &subscriptions)
    }

    public func load() {
        // TODO: Skip if outbox disabled, track didLoad, run on toggle on + !didLoad
        
        
        // include pubkeys from contact feeds (.type == "pubkeys" or nil) with .useOutbox enabled, and are active (.showAsTab)
        let contactFeedsPubkeys: Set<String> = Set(
            CloudFeed.fetchAll(context: Nostur.context())
                .filter { $0.useOutbox && $0.couldUseOutbox && $0.showAsTab }
                .flatMap { $0.contactPubkeys }
            )
        
        self.contactFeedPubkeys = contactFeedsPubkeys
        
        // Load from DB, then fetch more
        
        self.loadKind10002sFromDb { kind10002s in
            
            self.cp.queue.async(flags: .barrier) { [weak self] in
                self?.cp.setPreferredRelays(using: kind10002s)
            }
            
#if DEBUG
            L.sockets.debug("📤📤 Outbox: loaded \(kind10002s.count) from db")
#endif
            self.scheduleDeferredMaintenance()
        }
    }
    
    // Reload (call after custom feed with .useOutbox on is updated)
    public func reload() {
        
        // include pubkeys from contact feeds (.type == "pubkeys" or nil) with .useOutbox enabled, and are active (.showAsTab)
        let contactFeedsPubkeys: Set<String> = Set(
            CloudFeed.fetchAll(context: Nostur.context())
                .filter { $0.useOutbox && $0.couldUseOutbox && $0.showAsTab }
                .flatMap { $0.contactPubkeys }
            )
        
        let added = contactFeedsPubkeys.subtracting(self.contactFeedPubkeys)
        self.contactFeedPubkeys = contactFeedsPubkeys
        self.reloadPreferredRelaysFromDb()
        if !added.isEmpty {
            fetchBatches(
                OutboxRefreshPolicy.batches(from: added),
                since: nil,
                prefix: "OUTBOX-FEED-"
            )
        }
    }
    
    private func loadKind10002sFromDb(_ completion: (([NostrEssentials.Event]) -> Void)? = nil) {
        context.perform { [weak self] in
            guard let self else { return }
              
            L.og.debug("📤📤 Outbox: including \(self.contactFeedPubkeys.subtracting(self.follows).count) pubkeys from contact feeds in relay autopilot")
            
            let kind10002s: [NostrEssentials.Event] = Event.fetchReplacableEvents(10002, pubkeys: self.follows.union(self.contactFeedPubkeys), context: context)
                .map { event in
                    return event.toNostrEssentialsEvent()
                }
            completion?(kind10002s)
        }
    }
    
    private func reloadPreferredRelaysFromDb(_ completion: (() -> Void)? = nil) {
        loadKind10002sFromDb { kind10002s in
            self.cp.queue.async(flags: .barrier) { [weak self] in
                self?.cp.reloadPreferredRelays(kind10002s: kind10002s)
            }
            completion?()
        }
    }

    private func scheduleDeferredMaintenance(after delay: TimeInterval = OutboxRefreshPolicy.deferredDelay) {
        deferredMaintenanceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard IS_CATALYST || !self.isAppInBackground else { return }
            self.runDeferredMaintenance()
        }
        deferredMaintenanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private struct RefreshPhase {
        let batches: [Set<String>]
        let since: Int?
        let prefix: String
    }

    private func runDeferredMaintenance() {
        context.perform { [weak self] in
            guard let self else { return }
            let allAuthors = self.follows.union(self.contactFeedPubkeys)
            guard !allAuthors.isEmpty else { return }

            let storedEvents = Event.fetchReplacableEvents(10002, pubkeys: allAuthors, context: self.context)
            let storedAuthors = Set(storedEvents.map(\.pubkey))
            let missing = OutboxRefreshPolicy.missingAuthors(
                allAuthors: allAuthors,
                storedAuthors: storedAuthors
            )
            let known = allAuthors.subtracting(missing)
            let defaults = UserDefaults.standard
            let lastAudit = defaults.object(forKey: self.auditDefaultsKey) as? Date
            let lastRefresh = defaults.object(forKey: self.refreshDefaultsKey) as? Date
            let auditDue = OutboxRefreshPolicy.shouldAudit(lastAttempt: lastAudit)

            var phases: [RefreshPhase] = []
            if !missing.isEmpty {
                phases.append(RefreshPhase(
                    batches: OutboxRefreshPolicy.batches(from: missing),
                    since: nil,
                    prefix: "OUTBOX-MISSING-"
                ))
            }
            if auditDue {
                phases.append(RefreshPhase(
                    batches: OutboxRefreshPolicy.batches(from: known),
                    since: nil,
                    prefix: "OUTBOX-AUDIT-"
                ))
            }
            else if let lastRefresh, !known.isEmpty {
                phases.append(RefreshPhase(
                    batches: OutboxRefreshPolicy.batches(from: known),
                    since: Int(lastRefresh.addingTimeInterval(-OutboxRefreshPolicy.incrementalOverlap).timeIntervalSince1970),
                    prefix: "OUTBOX-INCREMENTAL-"
                ))
            }

#if DEBUG
            L.sockets.debug("📤📤 Outbox maintenance: \(allAuthors.count) authors, \(storedAuthors.count) stored, \(missing.count) missing, audit=\(auditDue)")
#endif
            self.fetchPhases(phases) { [weak self] completedAllBatches in
                guard let self else { return }
                if completedAllBatches {
                    let now = Date()
                    defaults.set(now, forKey: self.refreshDefaultsKey)
                    if auditDue {
                        defaults.set(now, forKey: self.auditDefaultsKey)
                    }
                }
                self.reloadPreferredRelaysFromDb()
            }
        }
    }

    private func fetchPhases(
        _ phases: [RefreshPhase],
        completedAllBatches: Bool = true,
        completion: @escaping (Bool) -> Void
    ) {
        guard let phase = phases.first else {
            completion(completedAllBatches)
            return
        }
        fetchBatches(phase.batches, since: phase.since, prefix: phase.prefix) { [weak self] phaseCompleted in
            self?.fetchPhases(
                Array(phases.dropFirst()),
                completedAllBatches: completedAllBatches && phaseCompleted,
                completion: completion
            )
        }
    }

    private func fetchBatches(
        _ batches: [Set<String>],
        since: Int?,
        prefix: String,
        completedAllBatches: Bool = true,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        guard let authors = batches.first else {
            completion(completedAllBatches)
            return
        }
        guard IS_CATALYST || !isAppInBackground else {
            scheduleDeferredMaintenance()
            return
        }

        let task = ReqTask(
            debounceTime: 3.0,
            prefix: prefix,
            reqCommand: { taskId in
                guard let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   subscriptionId: taskId,
                                   filters: [Filters(authors: authors, kinds: [10002], since: since)]
                    ).json()
                else { return }
#if DEBUG
                L.sockets.debug("📤📤 Outbox maintenance: fetching \(authors.count) relay lists (since=\(since?.description ?? "none"))")
#endif
                req(cm)
            },
            processResponseCommand: { [weak self] taskId, _, _ in
                guard let self else { return }
                self.reloadPreferredRelaysFromDb {
                    self.fetchBatches(
                        Array(batches.dropFirst()),
                        since: since,
                        prefix: prefix,
                        completedAllBatches: completedAllBatches,
                        completion: completion
                    )
                }
            },
            timeoutCommand: { [weak self] taskId in
#if DEBUG
                L.sockets.debug("📤📤 Outbox maintenance: batch timed out or returned no new relay lists")
#endif
                self?.fetchBatches(
                    Array(batches.dropFirst()),
                    since: since,
                    prefix: prefix,
                    completedAllBatches: false,
                    completion: completion
                )
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

// Takes a pubkey and tries to return inbox relays
public func getInboxRelays(forPubkey pubkey: String) -> Set<String> {
    let kind10002: Event? = Event.fetchReplacableEvent(10002, pubkey: pubkey, context: context())
    
    let readRelays: Set<String> = Set( kind10002?.fastTags.filter({ relay in
        relay.0 == "r" && (relay.2 == nil || relay.2 == "read")
    }).map { normalizeRelayUrl($0.1) } ?? [] )
                
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
    "wss://relay.getalby.com", // only for NWC connections
    "sendit.nosflare.com", // "Denied! This relay does not accept REQs."
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
