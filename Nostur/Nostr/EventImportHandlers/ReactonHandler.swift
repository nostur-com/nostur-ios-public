//
//  PinnedPostsHandler.swift
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
}
