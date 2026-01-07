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
    let participants = if nEvent.kind == .directMessage {
        allDMparticipants(nEvent) // including sender (.pubkey)
    } else { // .legacyDirectMessage
        Set([sender,receiverPubkey]) // just 1 sender and 1 receveiver
    }
    
    
    savedEvent.otherPubkey = receiverPubkey // TODO: Check do we still need this here?
    
    let groupId = if nEvent.kind == .directMessage {
        dmConversationId(nEvent: nEvent) // based on all participants
    } else { // .legacyDirectMessage
        CloudDMState.getConversationId(for: [sender,receiverPubkey]) // just 1 sender and 1 receveiver
    }
    savedEvent.groupId = groupId
    
    // Info we need in other context
    let accountPubkeys: Set<String> = AccountsState.shared.bgAccountPubkeys
    let savedEventDate = savedEvent.date
    
    // DMStates live in main so need to switch
    Task { @MainActor in
        // existing DMStates (as receiver to ourAccountPubkey)
        let existingDMStates = CloudDMState.fetchByParticipants(participants: participants, context: viewContext())
        
        // add any missing DMState (as receiver to ourAccountPubkey)
        let receiversWithMissingDMStates: Set<String> = accountPubkeys
            .filter { accountPubkey in
                return participants.contains(accountPubkey) && !existingDMStates.contains { dmState in
                    return (dmState.accountPubkey_ == accountPubkey && dmState.conversationId == dmConversationId(nEvent: nEvent))
                }
            }

        var didCreateNewDMState = false

        // Create new DM states if we have missing
        for accountPubkey in receiversWithMissingDMStates {
            let dmState = CloudDMState(context: viewContext())
            dmState.accountPubkey_ = accountPubkey
            dmState.contactPubkey_ = participants.subtracting([accountPubkey]).first
            dmState.participantPubkeys = participants
            if accountPubkeys.contains(sender) {
                dmState.accepted = true
                dmState.markedReadAt_ = savedEventDate
            }
            else {
                dmState.accepted = false
                dmState.initiatorPubkey_ = sender
            }
            dmState.lastMessageTimestamp_ = Date.init(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp))
            updateBlurb(dmState, nEvent: nEvent, context: viewContext())
            didCreateNewDMState = true
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
                updateBlurb(dmState, nEvent: nEvent, context: viewContext())
            }
        }
        
        // Notify views or whatever needs to know
        if didCreateNewDMState { // Don't need to save right away anymore?
            Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: true))
        } else {
            Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: false))
        }
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

func updateBlurb(_ dmState: CloudDMState, event: Event, context: NSManagedObjectContext) {
    // decrypt if kind 4
    if event.kind == 4, let accountPubkey = dmState.accountPubkey_ {
        if let account = try? CloudAccount.fetchAccount(publicKey: accountPubkey, context: context), let privateKey = account.privateKey {
            let keyPair = (publicKey: account.publicKey, privateKey: privateKey)
            
            let content = if event.pubkey == keyPair.publicKey, let firstP = event.firstP() {
                Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: firstP, content: event.content ?? "") ?? "(Encrypted content)"
            }
            else {
                Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: event.pubkey, content: event.content ?? "") ?? "(Encrypted content)"
            }
            // prefix blurb with "You: " if we sent it
            let fromName = accountPubkey == event.pubkey ? "You: " : ""
            dmState.blurb = "\(fromName)\(content)"
        }
    }
    else { // kind 14 is already decrypted rumor
        // prefix blurb with "You: " if we sent it
        let fromName = dmState.accountPubkey_ == event.pubkey ? "You: " : ""
        dmState.blurb = "\(fromName)\(event.content ?? "")"
    }
}

func updateBlurb(_ dmState: CloudDMState, nEvent: NEvent, context: NSManagedObjectContext) {
    // decrypt if kind 4
    if nEvent.kind.id == 4, let accountPubkey = dmState.accountPubkey_ {
        if let account = try? CloudAccount.fetchAccount(publicKey: accountPubkey, context: context), let privateKey = account.privateKey {
            let keyPair = (publicKey: account.publicKey, privateKey: privateKey)
            
            let content = if nEvent.publicKey == keyPair.publicKey, let firstP = nEvent.firstP() {
                Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: firstP, content: nEvent.content) ?? "(Encrypted content)"
            }
            else {
                Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: nEvent.publicKey, content: nEvent.content) ?? "(Encrypted content)"
            }
            // prefix blurb with "You: " if we sent it
            let fromName = accountPubkey == nEvent.publicKey ? "You: " : ""
            dmState.blurb = "\(fromName)\(content)"
        }
    }
    else { // kind 14 is already decrypted rumor
        // prefix blurb with "You: " if we sent it
        let fromName = dmState.accountPubkey_ == nEvent.publicKey ? "You: " : ""
        dmState.blurb = "\(fromName)\(nEvent.content)"
    }
}
