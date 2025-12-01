//
//  ReactionHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleReaction(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard nEvent.kind == .reaction else { return }
    
    if let lastE = nEvent.lastE() {
        savedEvent.reactionToId = lastE
        // Thread 927: "Illegal attempt to establish a relationship 'reactionTo' between objects in different contexts
        // here savedEvent is not saved yet, so appears it can crash on context, even when its the same context
        CoreDataRelationFixer.shared.addTask({
            if let reactionTo = Event.fetchEvent(id: lastE, context: context) {
                guard contextWontCrash([savedEvent, reactionTo], debugInfo: "JJ savedEvent.reactionTo = reactionTo") else { return }
                savedEvent.reactionTo = reactionTo
            }
        })
        
        if let otherPubkey =  savedEvent.reactionTo?.pubkey {
            savedEvent.otherPubkey = otherPubkey
        }
        if savedEvent.otherPubkey == nil, let lastP = nEvent.lastP() {
            savedEvent.otherPubkey = lastP
        }
    }
    
    
    
    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
    Event.updateLikeCountCache(savedEvent, content: nEvent.content, context: context)
    if let otherPubkey = savedEvent.otherPubkey, AccountsState.shared.bgAccountPubkeys.contains(otherPubkey) {
        // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
        ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Reactions, accountPubkey: otherPubkey))
    }
    if let reactionToId = savedEvent.reactionToId {
        ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Reactions, eventId: reactionToId))
        
        // Update own reactions cache
        if nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
            let reactionContent = nEvent.content
            Task { @MainActor in
                accountCache()?.addReaction(reactionToId, reactionType: reactionContent)
                sendNotification(.postAction, PostActionNotification(type: .reacted(nil, reactionContent), eventId: reactionToId))
            }
        }
    }
}
