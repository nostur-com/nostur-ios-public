//
//  DMHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleDM(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard nEvent.kind == .directMessage else { return }
    
    // needed to fetch contact in DMS: so event.firstP is in event.contacts
    savedEvent.otherPubkey = nEvent.firstP()
    
    if let contactPubkey = savedEvent.otherPubkey { // If we have a DM kind 4, but no p, then something is wrong
        if let dmState = CloudDMState.fetchExisting(nEvent.publicKey, contactPubkey: contactPubkey, context: context) {
            
            // if we already track the conversation, consider accepted if we replied to the DM
            // DM is sent from one of our current logged in pubkey
            if !dmState.accepted && AccountsState.shared.bgAccountPubkeys.contains(nEvent.publicKey) {
                dmState.accepted = true
                
                if let current = dmState.markedReadAt_, savedEvent.date > current {
                    dmState.markedReadAt_ = savedEvent.date
                }
                else if dmState.markedReadAt_ == nil {
                    dmState.markedReadAt_ = savedEvent.date
                }
            }
            // Let DirectMessageViewModel handle view updates
            DirectMessageViewModel.default.newMessage()
            DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
        }
        // Same but account / contact switched, because we support multiple accounts so we need to be able to track both ways
        else if let dmState = CloudDMState.fetchExisting(contactPubkey, contactPubkey: nEvent.publicKey, context: context) {
            
            // if we already track the conversation, consider accepted if we replied to the DM
            if !dmState.accepted && AccountsState.shared.bgAccountPubkeys.contains(nEvent.publicKey) {
                dmState.accepted = true
            }
            // Let DirectMessageViewModel handle view updates
            DirectMessageViewModel.default.newMessage()
            DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
        }
        else {
            // if we are sender with full account
            if AccountsState.shared.bgFullAccountPubkeys.contains(nEvent.publicKey) {
                let savedEventDate = savedEvent.date
                Task { @MainActor in
                    let dmState = CloudDMState(context: viewContext())
                    dmState.accountPubkey_ = nEvent.publicKey
                    dmState.contactPubkey_ = contactPubkey
                    dmState.accepted = true
                    dmState.markedReadAt_ = savedEventDate
                    DataProvider.shared().saveToDiskNow(.viewContext)
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage()
                }
                DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
            }
            
            // if we are receiver with full account
            else if AccountsState.shared.bgFullAccountPubkeys.contains(contactPubkey) {
                Task { @MainActor in
                    let dmState = CloudDMState(context: viewContext())
                    dmState.accountPubkey_ = contactPubkey
                    dmState.contactPubkey_ = nEvent.publicKey
                    dmState.accepted = false
                    DataProvider.shared().saveToDiskNow(.viewContext)
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage()
                }
                DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
            }
            
            // if we are sender with read only account
            else if AccountsState.shared.bgAccountPubkeys.contains(nEvent.publicKey) {
                let savedEventDate = savedEvent.date
                Task { @MainActor in
                    let dmState = CloudDMState(context: viewContext())
                    dmState.accountPubkey_ = nEvent.publicKey
                    dmState.contactPubkey_ = contactPubkey
                    dmState.accepted = true
                    dmState.markedReadAt_ = savedEventDate
                    DataProvider.shared().saveToDiskNow(.viewContext)
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage()
                }
                DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
            }
            
            // if we are receiver with read only account
            else if AccountsState.shared.bgAccountPubkeys.contains(contactPubkey) {
                Task { @MainActor in
                    let dmState = CloudDMState(context: viewContext())
                    dmState.accountPubkey_ = contactPubkey
                    dmState.contactPubkey_ = nEvent.publicKey
                    dmState.accepted = false
                    DataProvider.shared().saveToDiskNow(.viewContext)
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage()
                }
                DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
            }
        }
    }
}
