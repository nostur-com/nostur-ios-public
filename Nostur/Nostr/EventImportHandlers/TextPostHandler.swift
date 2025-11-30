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
    
    if nEvent.content == "#[0]", let firstE = nEvent.firstE() {
        savedEvent.isRepost = true
        
        savedEvent.firstQuoteId = firstE
        
        if let kind6firstQuote = kind6firstQuote {
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, kind6firstQuote], debugInfo: "#[0] savedEvent.firstQuote = kind6firstQuote") else { return }
                savedEvent.firstQuote = kind6firstQuote // got it passed in as parameter on saveEvent() already.
                
                // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
                savedEvent.otherPubkey = kind6firstQuote.pubkey
            })
        }
        else {
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT + UPDATE REPOST COUNT
            if let repostedEvent = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, repostedEvent], debugInfo: "II savedEvent.firstQuote = repostedEvent") else { return }
                    savedEvent.firstQuote = repostedEvent
                    
                    // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
                    savedEvent.otherPubkey = repostedEvent.pubkey
                })
                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
//                        repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
            }
            else if let firstP = nEvent.firstP() { // or lastP? not sure
                savedEvent.otherPubkey = firstP
            }
        }
    }
    
    if let replyToAtag = nEvent.replyToAtag() { // Comment on article
        if let dbArticle = Event.fetchReplacableEvent(aTag: replyToAtag.value, context: context) {
            savedEvent.replyToId = dbArticle.id
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, dbArticle], debugInfo: "HH savedEvent.replyTo = dbArticle") else { return }
                savedEvent.replyTo = dbArticle
            })
            
            dbArticle.addToReplies(savedEvent)
            dbArticle.repliesCount += 1
//                    dbArticle.repliesUpdated.send(dbArticle.replies_)
            ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: dbArticle.id, replies: dbArticle.replies_))
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
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, dbArticle], debugInfo: "GG savedEvent.replyToRoot = dbArticle") else { return }
                savedEvent.replyToRoot = dbArticle
            })
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
            CoreDataRelationFixer.shared.addTask({
                // Thread 24: "Illegal attempt to establish a relationship 'replyTo' between objects in different contexts
                // (when opening from bookmarks)
                guard contextWontCrash([savedEvent, parent], debugInfo: "FF savedEvent.replyTo = parent") else { return }
                savedEvent.replyTo = parent
            })
            // Illegal attempt to establish a relationship 'replyTo' between objects in different contexts
            parent.addToReplies(savedEvent)
            parent.repliesCount += 1
//                    replyTo.repliesUpdated.send(replyTo.replies_)
            ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: parent.id, replies: parent.replies_))
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
            
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, root], debugInfo: "EE savedEvent.replyToRoot = root") else { return }
                savedEvent.replyToRoot = root
            })
            
            // Thread 32193: "Illegal attempt to establish a relationship 'replyToRoot' between objects in different contexts (source = <Nostur.Event: 0x371850ee0> (entity: Event; id: 0x351b9e3e0 <x-coredata:///Event/tB769F78C-0ED3-427A-B8A2-BDDA94C71D1030798>; data: {\n    bookmarkedBy =     (\n    );\n    contact = \"0xafbaca1f2e1691dc <x-coredata://3DA0D6F2-885E-43D0-B952-9C23B7D82BA8/Contact/p12190>\";\n    content = \"Do you mind elaborating on \\U201crolling your own kind number is a heavy lift in practice\\U201d? \\n\\nIs it the choice of which kind number to use that\\U2019s the blocker? Are people hesitant to pick a new one and just\";\n    \"created_at\" = 1728407076;\n    dTag = \"\";\n    deletedById = nil;\n    dmAccepted = 0;\n    firstQuote = nil;\n    firstQuoteId = nil;\n    flags = \"\";\n    id = 10eeb3d72083929e9409750c6ad009f736297557b6f8e76bb320b3bd1e61bebd;\n    insertedAt = \"2024-10-10 19:27:50 +0000\";\n    isRepost = 0;\n    kind = 1;\n    lastSeenDMCreatedAt = 0;\n    likesCount = 0;\n    mentionsCount = 0;\n    mostRecentId = nil;\n    otherAtag"
            
            ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRoot, id: savedEvent.id, event: root))
            ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRootInverse, id:  root.id, event: savedEvent))
            if (savedEvent.replyToId == savedEvent.replyToRootId) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, root], debugInfo: "DD savedEvent.replyTo = root") else { return }
                    savedEvent.replyTo = root // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                })
                root.addToReplies(savedEvent)
                root.repliesCount += 1
                ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: root.id, replies: root.replies_))
                ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyTo, id: savedEvent.id, event: root))
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: root.id, replies: root.repliesCount))
            }
        }
    }
    
    // Finally, we have a reply to root set from aTag, but we still don't have a replyTo
    else if savedEvent.replyToRootId != nil, savedEvent.replyToId == nil {
        // so set replyToRoot (aTag) as replyTo
        savedEvent.replyToId = savedEvent.replyToRootId
        CoreDataRelationFixer.shared.addTask({
            guard let replyToRoot = savedEvent.replyToRoot, contextWontCrash([savedEvent, replyToRoot], debugInfo: "CC savedEvent.replyTo = replyToRoot") else { return }
            savedEvent.replyTo = replyToRoot
            
            if let parent = savedEvent.replyTo {
                parent.addToReplies(savedEvent)
                parent.repliesCount += 1
//                    replyTo.repliesUpdated.send(replyTo.replies_)
                ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: parent.id, replies: parent.replies_))
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: parent.id, replies: parent.repliesCount))
            }
        })
    }
    
    if let replyToId = savedEvent.replyToId, nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
        // Update own replied to cache
        Task { @MainActor in
            accountCache()?.addRepliedTo(replyToId)
            sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
        }
    }
    
    handleRepostInKind1(nEvent: nEvent, savedEvent: savedEvent, kind6firstQuote: kind6firstQuote, context: context)
}

func handleRepostInKind1(nEvent: NEvent, savedEvent: Event, kind6firstQuote: Event? = nil, context: NSManagedObjectContext) {
    // handle REPOST with normal mentions in .kind 1
    // TODO: handle first nostr:nevent or not?
    var alreadyCounted = false
    if let firstE = nEvent.firstMentionETag(), let replyToId = savedEvent.replyToId, firstE.id != replyToId { // also fQ not the same as replyToId
        savedEvent.firstQuoteId = firstE.id
        
        // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
        if let firstQuote = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, firstQuote], debugInfo: "BB savedEvent.firstQuote = firstQuote") else { return }
                savedEvent.firstQuote = firstQuote
            })
            
            if (firstE.tag[safe: 3] == "mention") {
//                    firstQuote.objectWillChange.send()
                firstQuote.mentionsCount += 1
                alreadyCounted = true
            }
        }
    }
    
    // hmm above firstQuote doesn't seem to handle #[0] at .content end and "e" without "mention as first tag, so special case?
    if !alreadyCounted && nEvent.content.contains("#[0]"), let firstE = nEvent.firstMentionETag() {
        savedEvent.firstQuoteId = firstE.id
        
        // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
        if let firstQuote = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, firstQuote], debugInfo: "AA savedEvent.firstQuote = firstQuote") else { return }
                savedEvent.firstQuote = firstQuote
            })
            
//                firstQuote.objectWillChange.send()
            firstQuote.mentionsCount += 1
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
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, waitingEvent], debugInfo: "waitingEvent.replyTo = savedEvent") else { return }
                waitingEvent.replyTo = savedEvent
            })
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyTo, id: waitingEvent.id, event: savedEvent)))
        }
        
        // Handle replies we already have, but root arrived just now
        if (waitingEvent.replyToRootId != nil) && (waitingEvent.replyToRootId == savedEvent.id) {
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([savedEvent, waitingEvent], debugInfo: "waitingEvent.replyToRoot = savedEvent") else { return }
                waitingEvent.replyToRoot = savedEvent
            })
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRoot, id: waitingEvent.id, event: savedEvent)))
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRootInverse, id: savedEvent.id, event: waitingEvent)))
        }
        
        
        // handle post with missing quoted post, and quoted post arrived just now
        // but not relevant for voice messsages
        if nEvent.kind == .shortVoiceMessage { continue }
        if (waitingEvent.firstQuoteId != nil) && (waitingEvent.firstQuoteId == savedEvent.id) {
            CoreDataRelationFixer.shared.addTask({
                // Ensure both objects have a valid context
                guard contextWontCrash([waitingEvent, savedEvent], debugInfo: "waitingEvent.firstQuote = savedEvent") else { return }
                waitingEvent.firstQuote = savedEvent
            })
            ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .firstQuote, id: waitingEvent.id, event: savedEvent)))
        }
    }
}

