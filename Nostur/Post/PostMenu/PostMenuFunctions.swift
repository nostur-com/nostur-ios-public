//
//  PostMenuFunctions.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import Foundation
import NostrEssentials

@MainActor
func pinToProfile(_ nrPost: NRPost) async throws {
    // check logged in account == nrPost.pubkey
    guard let account = account(), nrPost.pubkey == account.publicKey else { return }
    
    let rawSource = await withBgContext { _ in
        return nrPost.event?.toNEvent().eventJson()
    }
    
    guard let rawSource else { return }
    
    let latestPinned = NEvent(content: rawSource, kind: .latestPinned, tags: [
        NostrTag(["e", nrPost.id]),
        NostrTag(["k", nrPost.kind.description])
    ])
    
    let latestPinnedSigned = try await sign(nEvent: latestPinned, accountPubkey: account.publicKey)
    DispatchQueue.main.async {
        Unpublisher.shared.publishNow(latestPinnedSigned)
    }
    
    sendNotification(.didPinPost, PinPostInfo(pinEvent: latestPinnedSigned, pinnedPost: nrPost))
}

struct PinPostInfo: Identifiable {
    var id: String { pinEvent.id + pinnedPost.id }
    let pinEvent: NEvent
    let pinnedPost: NRPost
}

@MainActor
func addToHighlights(_ postToPin: NRPost) async throws {
    // check logged in account == nrPost.pubkey
    guard let account = account(), postToPin.pubkey == account.publicKey else { return }
    let accountPubkey = account.publicKey
    
    // Check relays for existing highlights list (pinned list)
    _ = try? await relayReq(Filters(authors: [account.publicKey], kinds: [10001]), accountPubkey: accountPubkey)
    
    // Fetch from DB
    let highlightsListNEvent: Nostur.NEvent? = await withBgContext { _ in
        let highlightsListEvent: Nostur.Event? = Event.fetchReplacableEvent(10001, pubkey: accountPubkey)
        return highlightsListEvent?.toNEvent()
    }
    
    if let highlightsListNEvent { // Add (but no duplicates)
        if highlightsListNEvent.fastTags.first(where: { $0.1 == postToPin.id }) == nil {
            var updatedHighlightsListNEvent = highlightsListNEvent
            updatedHighlightsListNEvent.tags.append(NostrTag(["e", postToPin.id]))
            
            // sign
            let signedEvent = try await sign(nEvent: updatedHighlightsListNEvent, accountPubkey: accountPubkey)
            
            // publish and save
            L.sockets.debug("Going to publish updated highlights list")
            DispatchQueue.main.async {
                Unpublisher.shared.publishNow(signedEvent)
            }
        }
        else {
            L.sockets.debug("Highlights list already contains pinned post")
        }
    }
    else { // Create new highlights list if none was found
        let newHighlightsList = NEvent(kind: .pinnedList,  tags: [NostrTag(["e", postToPin.id])])

        // sign
        let signedEvent = try await sign(nEvent: newHighlightsList, accountPubkey: accountPubkey)
        
        // publish and save
        L.sockets.debug("Going to publish new highlights list")
        DispatchQueue.main.async {
            Unpublisher.shared.publishNow(signedEvent)
        }
    }
}
