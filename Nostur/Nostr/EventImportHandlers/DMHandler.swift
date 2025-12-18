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
    
    // existing DMStates (as receiver to ourAccountPubkey)
    let existingDMStates = CloudDMState.fetchByParticipants(participants: participants, context: context)
    
    // add any missing DMState (as receiver to ourAccountPubkey)
    let receiversWithMissingDMStates: Set<String> = AccountsState.shared.bgAccountPubkeys
        .filter { accountPubkey in
            return participants.contains(accountPubkey) && !existingDMStates.contains { dmState in
                return (dmState.accountPubkey_ == accountPubkey && dmState.conversationId == dmConversationId(nEvent: nEvent))
            }
        }
    
    // Create new DM states if we have missing
    for accountPubkey in receiversWithMissingDMStates {
        let dmState = CloudDMState(context: context)
        dmState.accountPubkey_ = accountPubkey
        dmState.contactPubkey_ = participants.subtracting([accountPubkey]).first
        dmState.participantPubkeys = participants
        if AccountsState.shared.bgAccountPubkeys.contains(sender) {
            dmState.accepted = true
            let savedEventDate = savedEvent.date
            dmState.markedReadAt_ = savedEventDate
        }
        else {
            dmState.accepted = false
            dmState.initiatorPubkey_ = sender
        }
        dmState.lastMessageTimestamp_ = Date.init(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp))
        updateBlurb(dmState, event: savedEvent, context: context)
        DataProvider.shared().saveToDiskNow {
            Importer.shared.importedDMSub.send((conversationId: groupId, event: savedEvent, nEvent: nEvent, newDMStateCreated: true))
        }
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
            updateBlurb(dmState, event: savedEvent, context: context)
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
