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
    
    // Cache details from zap request on 9735 event
    guard let nZapRequest = Event.extractZapRequest(tags: nEvent.tags) else { return }
    
    if let firstE = nEvent.firstE() {
        savedEvent.zappedEventId = firstE
        if nZapRequest.publicKey == AccountsState.shared.activeAccountPublicKey {
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
        
        if nZapRequest.publicKey == AccountsState.shared.activeAccountPublicKey {
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
        savedEvent.otherPubkey = firstP
    }
    
    savedEvent.fromPubkey = nZapRequest.publicKey
    
    savedEvent.amount = Int64(nEvent.naiveSats)
    savedEvent.content = nZapRequest.content
    if let clientTag = nZapRequest.tags.first(where: { $0.type == "client" && $0.value.prefix(6) != "31990:" }) {
        savedEvent.cache1 = clientTag.value
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
