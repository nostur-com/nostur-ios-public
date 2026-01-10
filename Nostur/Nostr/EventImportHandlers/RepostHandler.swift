//
//  RepostHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

// Returns inner reposted Event or nil`
// This is Before .saveEvent()
func handleRepost(_ event: NEvent, relays: String, bgContext: NSManagedObjectContext) throws -> Event? {
    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
        if event.content == "" {
            if let firstE = event.firstE() {
                return Event.fetchEvent(id: firstE, context: bgContext)
            }
            return nil
        }
        else if let noteInNote = try? Importer.shared.decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
            if !Event.eventExists(id: noteInNote.id, context: bgContext) {
                
                guard try noteInNote.verified() else {
#if DEBUG
                    L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
#endif
                    throw ImportErrors.InvalidSignature
                }
                let kind6firstQuote = Event.saveEvent(event: noteInNote, relays: relays, context: bgContext)
                
                FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
                    NeedsUpdateInfo(event: kind6firstQuote)
                )
            }
            else {
                Event.updateRelays(noteInNote.id, relays: relays, context: bgContext)
            }
        }
    }
    return nil
}

// This is in .saveEvent()
// // kind6 - repost, the reposted post is put in as .firstQuote
func handleRepost(nEvent: NEvent, savedEvent: Event, kind6firstQuote: Event? = nil, context: NSManagedObjectContext) {
    guard nEvent.kind == .repost else { return }
    
    savedEvent.firstQuoteId = kind6firstQuote?.id ?? nEvent.firstE()
    
    if let firstQuoteId = savedEvent.firstQuoteId, nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
        // Update own reposted cache
        Task { @MainActor in
            accountCache()?.addReposted(firstQuoteId)
            sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: firstQuoteId))
        }
    }
    
    if let kind6firstQuote {
        // if we already have the firstQuote (reposted post), we use that .pubkey
        savedEvent.otherPubkey = kind6firstQuote.pubkey
        
        // We need to get firstQuote from db or cache
        if let firstE = nEvent.firstE() {
            if let repostedEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstE) {
                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
            }
            else if let repostedEvent = Event.fetchEvent(id: firstE, context: context) {
                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
            }
        }
    }
    else if let firstQuoteId = savedEvent.firstQuoteId {
        if let firstP = nEvent.firstP() { // or lastP?
            // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
            savedEvent.otherPubkey = firstP
        }
        
        guard let firstQuote = Event.fetchEvent(id: firstQuoteId, context: context) else { return }
        firstQuote.repostsCount = (firstQuote.repostsCount + 1)
        ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: firstQuote.id, reposts: firstQuote.repostsCount))
    }
    
    if let otherPubkey = savedEvent.otherPubkey, AccountsState.shared.bgAccountPubkeys.contains(otherPubkey) {
        // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
        ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Reposts, accountPubkey: otherPubkey))
    }
    
    if let repostedId = savedEvent.firstQuoteId {
        ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Reposts, eventId: repostedId))
        
        // Update own reposted cache
        if nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
            Task { @MainActor in
                accountCache()?.addReposted(repostedId)
                sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: repostedId))
            }
        }
    }
}

public enum ImportErrors: Error {
    
    case InvalidSignature
    case AlreadyHaveNewerReplacableEvent
}
