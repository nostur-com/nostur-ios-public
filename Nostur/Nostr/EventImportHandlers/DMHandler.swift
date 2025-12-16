//
//  DMHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData
import NostrEssentials

// Kind 4 handling, for now we can reuse for kind 14
func handleDM(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard nEvent.kind == .legacyDirectMessage || nEvent.kind == .directMessage else { return }
    
    // needed to fetch contact in DMS: so event.firstP is in event.contacts
    
    guard let receiverPubkey = nEvent.firstP() else { return } // if we have no p, something is wrong
    let sender = nEvent.publicKey
    let participants = allDMparticipants(nEvent) // including sender (.pubkey)
    
    savedEvent.otherPubkey = receiverPubkey // TODO: Check do we still need this here?
    
    let groupId = dmConversationId(nEvent: nEvent)
    savedEvent.groupId = groupId
    
    let existingDMStates = CloudDMState.fetchByParticipants(participants: participants, context: context)
    
    // Create new DM states if we have none yet
    guard !existingDMStates.isEmpty else {
        var didAddAsSender = false
        var addedAsReceiverPubkeys: Set<String> = []
        // if we are sender with full account
        if AccountsState.shared.bgFullAccountPubkeys.contains(sender) {
            let savedEventDate = savedEvent.date
            let dmState = CloudDMState(context: context)
            dmState.accountPubkey_ = sender
            dmState.contactPubkey_ = receiverPubkey // for non-updated clients
            dmState.participantPubkeys = participants
            dmState.accepted = true
            dmState.markedReadAt_ = savedEventDate
            dmState.lastMessageTimestamp_ = Date.init(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp))
            updateBlurb(dmState, event: savedEvent, context: context)
            DataProvider.shared().saveToDiskNow {
                Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: true))
            }
            didAddAsSender = true
        }
        
        // if we are one of the receivers with full account
        for participant in participants {
            if AccountsState.shared.bgFullAccountPubkeys.contains(participant) {
                let dmState = CloudDMState(context: context)
                dmState.accountPubkey_ = participant
                dmState.contactPubkey_ = receiverPubkey // for non-updated clients
                dmState.participantPubkeys = participants
                dmState.accepted = false
                dmState.lastMessageTimestamp_ = Date.init(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp))
                updateBlurb(dmState, event: savedEvent, context: context)
                DataProvider.shared().saveToDiskNow {
                    Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: true))
                }
                addedAsReceiverPubkeys.insert(participant)
            }
        }

        // if we are sender with read only account (and did not already add with full account
        if !didAddAsSender && AccountsState.shared.bgAccountPubkeys.contains(sender) {
            let savedEventDate = savedEvent.date
            let dmState = CloudDMState(context: context)
            dmState.accountPubkey_ = sender
            dmState.contactPubkey_ = receiverPubkey // for non-updated clients
            dmState.participantPubkeys = participants
            dmState.accepted = true
            dmState.markedReadAt_ = savedEventDate
            DataProvider.shared().saveToDiskNow {
                Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: true))
            }
        }
        
        // if we are one of the receivers with read only account
        for participant in participants {
            if addedAsReceiverPubkeys.contains(participant) { continue }  // skip if already added
            if AccountsState.shared.bgAccountPubkeys.contains(participant) {
                let dmState = CloudDMState(context: context)
                dmState.accountPubkey_ = participant
                dmState.contactPubkey_ = receiverPubkey // for non-updated clients
                dmState.participantPubkeys = participants
                dmState.accepted = false
                DataProvider.shared().saveToDiskNow {
                    Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: true))
                }
            }
        }
        return
    }
    
    // Update existing DM states
    for dmState in existingDMStates {
        // Consider accepted if we replied to the DM
        // DM is sent from one of our account pubkeys
        if !dmState.accepted && AccountsState.shared.bgAccountPubkeys.contains(nEvent.publicKey) {
            dmState.accepted = true
            
            if let current = dmState.markedReadAt_, savedEvent.date > current {
                dmState.markedReadAt_ = savedEvent.date
            }
            else if dmState.markedReadAt_ == nil {
                dmState.markedReadAt_ = savedEvent.date
            }
        }
        
        if nEvent.createdAt.timestamp > Int(dmState.lastMessageTimestamp_?.timeIntervalSince1970 ?? 0) {
            dmState.lastMessageTimestamp_ = Date.init(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp))
        }
        Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: false))
    }
}

func allDMparticipants(_ nEvent: NEvent) -> Set<String> {
    return Set(nEvent.pTags() + [nEvent.publicKey])
}

func dmConversationId(nEvent: NEvent) -> String {
    return CloudDMState.getConversationId(for: allDMparticipants(nEvent))
}

func allDMparticipants(_ event: Event) -> Set<String> {
    return Set(event.pTags() + [event.pubkey])
}

func dmConversationId(event: Event) -> String {
    return CloudDMState.getConversationId(for: allDMparticipants(event))
}
