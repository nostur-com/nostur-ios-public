//
//  LVM+relays.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/07/2023.
//

import Foundation
import CoreData

// LVM things related to feeds of relays
extension LVM {
    
    // FETCHES NOTHING, BUT AFTER THAT IS REALTIME FOR NEW EVENTS
    func fetchRelaysRealtimeSinceNow(subscriptionId:String) {
        guard !relays.isEmpty else { return }
        let now = NTimestamp(date: Date.now)
        req(RM.getGlobalFeedEvents(subscriptionId: subscriptionId, since: now), activeSubscriptionId: subscriptionId, relays: relays)
    }
    
    // FETCHES ALL NEW, UNTIL NOW
    func fetchRelaysNewestUntilNow(subscriptionId:String) {
        let now = NTimestamp(date: Date.now)
        guard !relays.isEmpty else { return }
        req(RM.getGlobalFeedEvents(subscriptionId: "G-CATCHUP-" + subscriptionId, until: now), relays: relays)
    }
    
    func fetchRelaysNewerSince(subscriptionId:String, since: NTimestamp) {
        guard !relays.isEmpty else { return }
        req(RM.getGlobalFeedEvents(subscriptionId: "G-RESUME-" + subscriptionId, since: since), relays: relays)
    }
    
//    func fetchRelaysNextPage() {
//        guard !relays.isEmpty else { return }
//        guard let last = self.nrPostLeafs.last else { return }
//        let until = NTimestamp(date: last.createdAt)
//        req(RM.getGlobalFeedEvents(limit: 100,
//                                  subscriptionId: "G-PAGE-" + UUID().uuidString,
//                                  until: until), relays: relays)
//    }
}


extension Event {
    
    static func postsByRelays(_ relays:Set<RelayData>, mostRecent:Event, hideReplies:Bool = false) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        let cutOffPoint = mostRecent.created_at - (15 * 60)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = 50 // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, QUERY_FOLLOWING_KINDS, regex, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, QUERY_FOLLOWING_KINDS, regex, blockedPubkeys)
        }
        return fr
    }
    
    
    static func postsByRelays(_ relays:Set<RelayData>, until:Event, hideReplies:Bool = false) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        let cutOffPoint = until.created_at + (1 * 60)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]

        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = 50 // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, QUERY_FOLLOWING_KINDS, regex, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, QUERY_FOLLOWING_KINDS, regex, blockedPubkeys)
        }
        return fr
    }
    
    static func postsByRelays(_ relays:Set<RelayData>, lastAppearedCreatedAt:Int64 = 0, hideReplies:Bool = false) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 8) // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        
        // get 50 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        frBefore.fetchLimit = 50 // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, regex)
        }
        else {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND relays MATCHES %@ AND flags != \"is_update\"", cutOffPoint, QUERY_FOLLOWING_KINDS, blockedPubkeys, regex)
        }
        
        let newFirstEvent = try? bg().fetch(frBefore).last
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffPoint
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = 50 // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", newCutOffPoint, QUERY_FOLLOWING_KINDS, regex)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\"", newCutOffPoint, QUERY_FOLLOWING_KINDS, regex)
        }
        return fr
    }
    
    
    static func postsByRelays(_ relays:Set<RelayData>, until cutOffPoint: Int64 = Int64(Date().timeIntervalSince1970), hideReplies:Bool = false) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]

        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = 50 // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, QUERY_FOLLOWING_KINDS, regex, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, QUERY_FOLLOWING_KINDS, regex, blockedPubkeys)
        }
        return fr
    }
}
