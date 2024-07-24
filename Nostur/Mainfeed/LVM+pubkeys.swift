//
//  LVM+pubkeys.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/07/2023.
//

import Foundation
import CoreData
import NostrEssentials

typealias CM = NostrEssentials.ClientMessage

let FETCH_FOLLOWING_KINDS: Set<Int> = [0,1,5,6,9802,30023,34235,30311,10002]
let QUERY_FOLLOWING_KINDS: Set<Int> = [1,6,9802,30023,34235]
let QUERY_FETCH_LIMIT = 50 // Was 25 before, but seems we are missing posts, maybe too much non WoT-hashtag coming back. Increase limit or split query? or could be the time cutoff is too short/strict

// LVM things related to feeds of pubkeys
extension LVM {
    // FETCHES NOTHING, BUT AFTER THAT IS REALTIME FOR NEW EVENTS
    func fetchRealtimeSinceNow(subscriptionId: String) {
        guard !pubkeys.isEmpty else { return }
        let now = NTimestamp(date: Date.now)
        
        var filters: [Filters] = []
        
        let followingContactsFilter = Filters(
            authors: Set(self.pubkeys), // seems prefixes are no longer in NIP-01
            kinds: FETCH_FOLLOWING_KINDS,
            since: now.timestamp, limit: 5000)
        
        filters.append(followingContactsFilter)
        
        if !hashtags.isEmpty {
            let followingHashtagsFilter = Filters(
                kinds: FETCH_FOLLOWING_KINDS,
                tagFilter: TagFilter(tag:"t", values: Array(hashtags).map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }),
                since: now.timestamp)
            filters.append(followingHashtagsFilter)
        }
        
        // TODO: Add toggle on .pubkeys custom feeds so it can work also for non-"Following"
        if self.id == "Following" {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: filters), activeSubscriptionId: subscriptionId)
        }
        else if let message = CM(type: .REQ, subscriptionId: subscriptionId, filters: filters).json() {
            req(message, activeSubscriptionId: subscriptionId)
        }
    }
    
    // FETCHES ALL NEW, UNTIL NOW
    func fetchNewestUntilNow(subscriptionId: String) {
        let now = NTimestamp(date: Date.now)
        guard !pubkeys.isEmpty else { return }
        
        
        var filters: [Filters] = []
        
        let followingContactsFilter = Filters(
            authors: Set(self.pubkeys), // seems prefixes are no longer in NIP-01
            kinds: FETCH_FOLLOWING_KINDS,
            until: now.timestamp, limit: 5000)
        
        filters.append(followingContactsFilter)
        
        if !hashtags.isEmpty {
            let followingHashtagsFilter = Filters(
                kinds: FETCH_FOLLOWING_KINDS,
                tagFilter: TagFilter(tag:"t", values: Array(hashtags)),
                until: now.timestamp, limit: 5000)
            filters.append(followingHashtagsFilter)
        }
        
        // TODO: Add toggle on .pubkeys custom feeds so it can work also for non-"Following"
        if self.id == "Following" {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "CATCHUP-" + subscriptionId, filters: filters))
        }
        else if let message = CM(type: .REQ, subscriptionId: "CATCHUP-" + subscriptionId, filters: filters).json() {
            req(message)
        }
    }
    
    func fetchNewerSince(subscriptionId: String, since: NTimestamp) {
        guard !pubkeys.isEmpty else { return }
        
        var filters: [Filters] = []
        
        let followingContactsFilter = Filters(
            authors: Set(self.pubkeys), // seems prefixes are no longer in NIP-01
            kinds: FETCH_FOLLOWING_KINDS,
            since: since.timestamp, limit: 5000)
        
        filters.append(followingContactsFilter)        
        
        if !hashtags.isEmpty {
            let followingHashtagsFilter = Filters(
                kinds: FETCH_FOLLOWING_KINDS,
                tagFilter: TagFilter(tag:"t", values: Array(hashtags)),
                since: since.timestamp, limit: 5000)
            filters.append(followingHashtagsFilter)
        }
        
        
        // TODO: Add toggle on .pubkeys custom feeds so it can work also for non-"Following"
        if self.id == "Following" {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "RESUME-" + subscriptionId, filters: filters))
        }
        else if let message = CM(type: .REQ, subscriptionId: "RESUME-" + subscriptionId, filters: filters).json() {
            req(message)
        }
    }
    
    func fetchNextPage() {
        guard !pubkeys.isEmpty else { return }
        guard let last = self.nrPostLeafs.last else { return }
        let until = NTimestamp(date: last.createdAt)
        
        var filters: [Filters] = []
        
        let followingContactsFilter = Filters(
            authors: Set(self.pubkeys), // seems prefixes are no longer in NIP-01
            kinds: FETCH_FOLLOWING_KINDS,
            until: until.timestamp, limit: 100)
        
        filters.append(followingContactsFilter)
        
        if !hashtags.isEmpty {
            let followingHashtagsFilter = Filters(
                kinds: FETCH_FOLLOWING_KINDS,
                tagFilter: TagFilter(tag:"t", values: Array(hashtags)),
                until: until.timestamp, limit: 100)
            filters.append(followingHashtagsFilter)
        }
        
        if self.id == "Following" {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "PAGE-" + UUID().uuidString, filters: filters))
        }
        else if let message = CM(type: .REQ, subscriptionId: "PAGE-" + UUID().uuidString, filters: filters).json() {
            req(message)
        }
    }
    
    var hashtagRegex: String? {
        if !hashtags.isEmpty {
            let regex = ".*(" + hashtags.map {
                NSRegularExpression.escapedPattern(for: serializedT($0))
            }.joined(separator: "|") + ").*"
            return regex
        }
        
        return nil
    }
}


extension Event {
    
    // TODO: Optimize tagsSerialized / hashtags matching
    static func postsByPubkeys(_ pubkeys: Set<String>, mostRecent: Event, hideReplies: Bool = false, hashtagRegex:String? = nil) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let cutOffPoint = mostRecent.created_at - (15 * 60)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        if let hashtagRegex = hashtagRegex {
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, pubkeys, hashtagRegex)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND flags != \"is_update\"", cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, pubkeys, hashtagRegex)
            }
        }
        else {
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint,  pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
            }
        }
        return fr
    }
    
    
    static func postsByPubkeys(_ pubkeys: Set<String>, until: Event, hideReplies: Bool = false, hashtagRegex: String? = nil) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let cutOffPoint = until.created_at + (1 * 60)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        if let hashtagRegex = hashtagRegex {
            
            let after = until.created_at - (8 * 3600) // we need just 25 posts, so don't scan too far back, the regex match on tagsSerialized seems slow
            
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at > %i AND created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", after, cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, pubkeys, hashtagRegex)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at > %i AND created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND flags != \"is_update\"", after, cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, pubkeys, hashtagRegex)
            }
        }
        else {
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
            }
        }
        return fr
    }
    
    static func postsByPubkeys(_ pubkeys: Set<String>, lastAppearedCreatedAt: Int64 = 0, hideReplies: Bool = false, hashtagRegex: String? = nil) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8) // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        
        // get 15 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        frBefore.fetchLimit = QUERY_FETCH_LIMIT
        if let hashtagRegex = hashtagRegex {
            if hideReplies {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, pubkeys, hashtagRegex)
            }
            else {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND flags != \"is_update\"", cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, pubkeys, hashtagRegex)
            }
        }
        else {
            if hideReplies {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
            }
            else {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
            }
        }
        
        let newFirstEvent = try? bg().fetch(frBefore).last
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffPoint
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", newCutOffPoint, pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", newCutOffPoint,  pubkeys, QUERY_FOLLOWING_KINDS, blockedPubkeys)
        }
        return fr
    }
}
