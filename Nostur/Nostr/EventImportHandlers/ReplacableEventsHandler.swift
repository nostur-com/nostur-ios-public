//
//  ReplacableEventHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleReplacableEvent(nEvent: NEvent, context: NSManagedObjectContext) {
    guard (nEvent.kind.id >= 10000 && nEvent.kind.id < 20000) else { return }
    
    // delete older events
    let r = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
    r.predicate = NSPredicate(format: "kind == %d AND pubkey == %@ AND created_at < %d", nEvent.kind.id, nEvent.publicKey, nEvent.createdAt.timestamp)
    let batchDelete = NSBatchDeleteRequest(fetchRequest: r)
    batchDelete.resultType = .resultTypeCount
    
    do {
        _ = try context.execute(batchDelete) as! NSBatchDeleteResult
    } catch {
        L.og.error("🔴🔴 Failed to delete older replaceable events for \(nEvent.id)")
    }
}

// Handle replacable event (NIP-33)
func handleAddressableReplacableEvent(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard (nEvent.kind.id >= 30000 && nEvent.kind.id < 40000) else { return }
         
    savedEvent.dTag = nEvent.tags.first(where: { $0.type == "d" })?.value ?? ""
    // update older events:
    // 1. set pointer to most recent (this one)
    // 2. set "is_update" flag on this one so it doesn't show up as new in feed
    let r = Event.fetchRequest()
    r.predicate = NSPredicate(format: "dTag == %@ AND kind == %d AND pubkey == %@", savedEvent.dTag, savedEvent.kind, nEvent.publicKey)

    var existingEventIds = Set<String>() // need to repoint all replies to older articles to the newest id
    
    // Set pointer on older events to the latest event id
    if let existingEvents = try? context.fetch(r) {
        
        // existingEvents will already include the savedEvent event also (can also be older one, if from relay that doesn't have latest
        let newestFirst = existingEvents.sorted { $0.created_at > $1.created_at }
        
        // most recent event (.created_at)
        if let first = newestFirst.first {
            // .mostRecentId should be nil
            first.mostRecentId = nil
            
            // if we already had this article, mark this one as "is_update" so it doesn't reappear in feed
            if existingEvents.count > 1 && first.id == savedEvent.id {
                savedEvent.flags = "is_update" // is supdate, don't reappear in feed
            }
            
            // older events
            for existingEvent in newestFirst.dropFirst() {
                existingEvent.mostRecentId = first.id
                existingEventIds.insert(existingEvent.id)
            }
            
            
            
            // Find existing replies referencing this event (can only be replyToRootId = "3XXXX:pubkey:dTag", or replyToRootId = "<older article ids>")
            // also do for replyToId
            if savedEvent.kind == 30023 { // Only do this for articles
                existingEventIds.insert(savedEvent.aTag)
                let fr = Event.fetchRequest()
                fr.predicate = NSPredicate(format: "kind IN {1,1111,1244} AND replyToRootId IN %@", existingEventIds)
                if let existingReplies = try? context.fetch(fr) {
                    for existingReply in existingReplies {
                        existingReply.replyToRootId = first.id
                        existingReply.replyToRoot = first
                    }
                }
                
                let fr2 = Event.fetchRequest()
                fr2.predicate = NSPredicate(format: "kind IN {1,1111,1244} AND replyToId IN %@", existingEventIds)
                if let existingReplies = try? context.fetch(fr) {
                    for existingReply in existingReplies {
                        existingReply.replyToId = first.id
                        existingReply.replyTo = first
                    }
                }
            }
        }
    }

    if Set([30311]).contains(savedEvent.kind) { // Only update views for kinds that need it (so far: 30311)
        ViewUpdates.shared.replacableEventUpdate.send(savedEvent)
    }
}
