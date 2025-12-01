//
//  ZapHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleZap(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard nEvent.kind == .zapNote else { return }
    
    // save 9734 seperate
    // so later we can do --> event(9735).zappedEvent(9734).contact
    let nZapRequest = Event.extractZapRequest(tags: nEvent.tags)
    if (nZapRequest != nil) {
        let zapRequest = Event.saveZapRequest(event: nZapRequest!, context: context)
        
        
        CoreDataRelationFixer.shared.addTask({
            guard contextWontCrash([savedEvent, zapRequest], debugInfo: "OO  savedEvent.zapFromRequest = zapRequest") else { return }
            savedEvent.zapFromRequest = zapRequest
        })
        if let firstE = nEvent.firstE() {
            savedEvent.zappedEventId = firstE
            
            if let awaitingEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstE) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, awaitingEvent], debugInfo: "OO savedEvent.zappedEvent = awaitingEvent") else { return }
                    savedEvent.zappedEvent = awaitingEvent
                })
                 // Thread 3273: "Illegal attempt to establish a relationship 'zappedEvent' between objects in different contexts
                // _PFManagedObject_coerceValueForKeyWithDescription
                // _sharedIMPL_setvfk_core
            }
            else {
                CoreDataRelationFixer.shared.addTask({
                    if let zappedEvent = Event.fetchEvent(id: firstE, context: context) {
                        guard contextWontCrash([savedEvent, zappedEvent], debugInfo: "NN savedEvent.zappedEvent = zappedEvent") else { return }
                        savedEvent.zappedEvent = zappedEvent
                    }
                })
            }
            if zapRequest.pubkey == AccountsState.shared.activeAccountPublicKey {
                savedEvent.zappedEvent?.zapState = .zapReceiptConfirmed
                ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: savedEvent.pubkey, eTag: savedEvent.zappedEventId, zapState: .zapReceiptConfirmed))
                
                // Update own zapped cache
                Task { @MainActor in
                    accountCache()?.addZapped(firstE)
                    sendNotification(.postAction, PostActionNotification(type: .zapped, eventId: firstE))
                }
            }
        }
        if let firstA = nEvent.firstA() {
            savedEvent.zappedEventId = firstA
            savedEvent.otherAtag = firstA
            
            if let awaitingEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstA) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, awaitingEvent], debugInfo: "MM savedEvent.zappedEvent = awaitingEvent") else { return }
                    savedEvent.zappedEvent = awaitingEvent
                })
                // Thread 3273: "Illegal attempt to establish a relationship 'zappedEvent' between objects in different contexts
                // _PFManagedObject_coerceValueForKeyWithDescription
                // _sharedIMPL_setvfk_core
            }
            else {
                CoreDataRelationFixer.shared.addTask({
                    if let zappedEvent = Event.fetchEvent(id: firstA, context: context) {
                        guard contextWontCrash([savedEvent, zappedEvent], debugInfo: "LL savedEvent.zappedEvent = zappedEvent") else { return }
                        savedEvent.zappedEvent = zappedEvent
                    }
                })
            }
            if zapRequest.pubkey == AccountsState.shared.activeAccountPublicKey {
                savedEvent.zappedEvent?.zapState = .zapReceiptConfirmed
                ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: savedEvent.pubkey, aTag: firstA, zapState: .zapReceiptConfirmed))
                // TODO: How to handle a tag here?? need to update cache and reading from cache if its aTag instead of id
                // Update own zapped cache
//                        Task { @MainActor in
//                            accountCache()?.addZapped(firstA)
//                        sendNotification(.postAction, PostActionNotification(type: .zapped, eventId: firstA))
//                        }
            }
        }
        if let firstP = nEvent.firstP() {
//                    savedEvent.objectWillChange.send()
            savedEvent.otherPubkey = firstP
            if let zappedContact = Contact.fetchByPubkey(firstP, context: context) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, zappedContact], debugInfo: "KK savedEvent.zappedContact = zappedContact") else { return }
                    savedEvent.zappedContact = zappedContact
                })
            }
        }
    }
    
    // bolt11 -- replaced with naiveBolt11Decoder
    //            if let bolt11 = event.bolt11() {
    //                let invoice = Invoice.fromStr(s: bolt11)
    //                if let parsedInvoice = invoice.getValue() {
    //                    savedEvent.cachedSats = Double((parsedInvoice.amountMilliSatoshis() ?? 0) / 1000)
    //                }
    //            }
    
    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
    Event.updateZapTallyCache(savedEvent, context: context)
    
    if let otherPubkey = savedEvent.otherPubkey, AccountsState.shared.bgAccountPubkeys.contains(otherPubkey) {
        // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
        ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Zaps, accountPubkey: otherPubkey))
    }
    
    if let zappedEventId = savedEvent.zappedEventId {
        ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Zaps, eventId: zappedEventId))
    }
}
