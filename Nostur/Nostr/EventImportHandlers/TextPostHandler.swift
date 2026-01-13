//
//  TextPostHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleTextPost(nEvent: NEvent, savedEvent: Event, kind6firstQuote: Event? = nil, context: NSManagedObjectContext) {
    guard nEvent.kind == .textNote else { return }
    
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
    }
     
    // Original replyTo/replyToRoot handling, don't overwrite aTag handling
        
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
    
    // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO. AND ROOT IS NOT ALREADY SET FROM ROOTATAG
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
    
    // Finally, we have a reply to root set from aTag, but we still don't have a replyTo
    else if savedEvent.replyToRootId != nil, savedEvent.replyToId == nil {
        // so set replyToRoot (aTag) as replyTo
        savedEvent.replyToId = savedEvent.replyToRootId
    }
    
    if let replyToId = savedEvent.replyToId, nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
        // Update own replied to cache
        Task { @MainActor in
            accountCache()?.addRepliedTo(replyToId)
            sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
        }
    }
    
    // UPDATE THINGS THAT THIS EVENT RELATES TO (MENTIONS)
    // First handle mentions NIP-10: Those marked with "mention" denote a quoted or reposted event id.
    if let mentionEtags = TagsHelpers(nEvent.tags).newerMentionEtags() {
        CoreDataRelationFixer.shared.addTask({
            for etag in mentionEtags {
                if let mentioningEvent = Event.fetchEvent(id: etag.id, context: context) {
                    guard contextWontCrash([mentioningEvent], debugInfo: "updateMentionsCountCache") else { return }
                    mentioningEvent.mentionsCount = (mentioningEvent.mentionsCount + 1)
                }
            }
        })
    }

    // Reposts in kind 1 (old style)
    handleRepostInKind1(nEvent: nEvent, savedEvent: savedEvent, kind6firstQuote: kind6firstQuote, context: context)
}

func handleRepostInKind1(nEvent: NEvent, savedEvent: Event, kind6firstQuote: Event? = nil, context: NSManagedObjectContext) {
    // handle REPOST with normal mentions in .kind 1
    var alreadyCounted = false
    
    if nEvent.content == "#[0]", let firstE = nEvent.firstE() { // Old repost structure
        
        savedEvent.firstQuoteId = firstE
        alreadyCounted = true
        
        if let kind6firstQuote = kind6firstQuote {
            // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
            savedEvent.otherPubkey = kind6firstQuote.pubkey
        }
        else {
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT + UPDATE REPOST COUNT
            if let repostedEvent = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
                savedEvent.otherPubkey = repostedEvent.pubkey
                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
            }
            else if let firstP = nEvent.firstP() { // or lastP? not sure
                savedEvent.otherPubkey = firstP
            }
        }
    }
    
    if !alreadyCounted, let firstE = nEvent.firstMentionETag(), let replyToId = savedEvent.replyToId, firstE.id != replyToId { // also fQ not the same as replyToId
        savedEvent.firstQuoteId = firstE.id
        
        // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
        if let firstQuote = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
            if (firstE.tag[safe: 3] == "mention") {
                firstQuote.mentionsCount += 1
                savedEvent.otherPubkey = firstQuote.pubkey
                alreadyCounted = true
            }
        }
    }
    
    // hmm above firstQuote doesn't seem to handle #[0] at .content end and "e" without "mention as first tag, so special case?
    if !alreadyCounted && nEvent.content.contains("#[0]"), let firstE = nEvent.firstMentionETag() {
        savedEvent.firstQuoteId = firstE.id
        
        if let kind6firstQuote = kind6firstQuote {
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
            kind6firstQuote.mentionsCount += 1
            savedEvent.otherPubkey = kind6firstQuote.pubkey
            
            kind6firstQuote.repostsCount = (kind6firstQuote.repostsCount + 1)
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: kind6firstQuote.id, reposts: kind6firstQuote.repostsCount))
        }
        else if let firstQuote = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
            firstQuote.mentionsCount += 1
            savedEvent.otherPubkey = firstQuote.pubkey
            
            firstQuote.repostsCount = (firstQuote.repostsCount + 1)
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: firstQuote.id, reposts: firstQuote.repostsCount))
        }
    }
}

func handlePostRelations(nEvent: NEvent, savedEvent: Event, kind6firstQuote: Event? = nil, context: NSManagedObjectContext) {
    guard nEvent.kind == .textNote || nEvent.kind == .shortVoiceMessage else { return }
    
    // IF we already have replies, need to link them to this root or parent:
    // or link post to embeded post (.firstQuote)
    let awaitingEvents = EventRelationsQueue.shared.getAwaitingBgEvents()
    
    for waitingEvent in awaitingEvents {
        
        // Handle replies we already have, but parent arrived just now
        if (waitingEvent.replyToId != nil) && (waitingEvent.replyToId == savedEvent.id) {
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyTo, id: waitingEvent.id, event: savedEvent)))
        }
        
        // Handle replies we already have, but root arrived just now
        if (waitingEvent.replyToRootId != nil) && (waitingEvent.replyToRootId == savedEvent.id) {
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRoot, id: waitingEvent.id, event: savedEvent)))
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRootInverse, id: savedEvent.id, event: waitingEvent)))
        }
        
        
        // handle post with missing quoted post, and quoted post arrived just now
        // but not relevant for voice messsages
        if nEvent.kind == .shortVoiceMessage { continue }
        if (waitingEvent.firstQuoteId != nil) && (waitingEvent.firstQuoteId == savedEvent.id) {
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .firstQuote, id: waitingEvent.id, event: savedEvent)))
        }
    }
}

