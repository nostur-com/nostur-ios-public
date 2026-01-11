//
//  CommentHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

// Handle (Voice) comment (comment/reply)
func handleComment(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard NIP22_COMMENT_KINDS.contains(nEvent.kind.id) else { return }
    
    // THIS EVENT REPLYING TO SOMETHING
    // CACHE THE REPLY "E" IN replyToId
    if let replyToEtag = nEvent.replyToEtag(), savedEvent.replyToId == nil {
        savedEvent.replyToId = replyToEtag.id
        
        // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
        if let parent = Event.fetchEvent(id: replyToEtag.id, context: context) {
            parent.repliesCount += 1
            ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: parent.id, replies: parent.replies))
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: parent.id, replies: parent.repliesCount))
        }
    }
    
    // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO. AND ROOT IS NOT ALREADY SET FROM ROOT E TAG
    // DO THE SAME AS WITH THE REPLY BEFORE
    if let replyToRootEtag = nEvent.replyToRootEtag(), savedEvent.replyToRootId == nil {
        savedEvent.replyToRootId = replyToRootEtag.id
        // Need to put it in queue to fix relations for replies to root / grouped replies
        //                EventRelationsQueue.shared.addAwaitingEvent(savedEvent, debugInfo: "saveEvent.123")
        
        let replyToRootIsSameAsReplyTo = savedEvent.replyToId == replyToRootEtag.id
        
        if (savedEvent.replyToId == nil) {
            savedEvent.replyToId = savedEvent.replyToRootId // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
        }
        
        if !replyToRootIsSameAsReplyTo, let root = Event.fetchEvent(id: replyToRootEtag.id, context: context) {
            
            ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRoot, id: savedEvent.id, event: root))
            ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRootInverse, id:  root.id, event: savedEvent))
            if (savedEvent.replyToId == savedEvent.replyToRootId) {
                root.repliesCount += 1
                ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: root.id, replies: root.replies))
                ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyTo, id: savedEvent.id, event: root))
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: root.id, replies: root.repliesCount))
            }
        }
    }
    
    // Finally, we have a reply to root set from e tag, but we still don't have a replyTo
    else if savedEvent.replyToRootId != nil, savedEvent.replyToId == nil {
        // so set replyToRoot as replyTo
        savedEvent.replyToId = savedEvent.replyToRootId
    }
    
    if let replyToId = savedEvent.replyToId, nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
        // Update own replied to cache
        Task { @MainActor in
            accountCache()?.addRepliedTo(replyToId)
            sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
        }
    }
    
    // If still nothing, check for reply to A/a tag
    guard savedEvent.replyToId == nil else { return }
    
    if let replyToAtag = nEvent.replyToAtag() { // Comment on article
        if let dbArticle = Event.fetchReplacableEvent(aTag: replyToAtag.value, context: context) {
            savedEvent.replyToId = dbArticle.id
            
            dbArticle.repliesCount += 1
            ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: dbArticle.id, replies: dbArticle.replies))
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: dbArticle.id, replies: dbArticle.repliesCount))
        }
        else {
            // we don't have the article yet, store aTag in replyToId
            savedEvent.replyToId = replyToAtag.value
        }
    }
    else if let replyToRootAtag = nEvent.replyToRootAtag() {
        // Comment has article as root, but replying to other comment, not to article.
        if let dbArticle = Event.fetchReplacableEvent(aTag: replyToRootAtag.value, context: context) {
            savedEvent.replyToRootId = dbArticle.id
        }
        else {
            // we don't have the article yet, store aTag in replyToRootId
            savedEvent.replyToRootId = replyToRootAtag.value
        }
        
        // if there is no replyTo (e or a) then the replyToRoot is the replyTo
        // but check first if we maybe have replyTo from e tags
        savedEvent.replyToId = replyToRootAtag.value
    }
    
}
