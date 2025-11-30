//
//  PinnedPostsHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handlePinnedPosts(_ event: NEvent, relays: String, bgContext: NSManagedObjectContext) throws {
    if event.kind == .latestPinned, let firstE = event.firstE() {
        // if we don't already have the to be pinned post (in .content), we decode and save it
        if !Event.eventExists(id: firstE, context: bgContext) && event.content.prefix(2) == #"{""# {
            if let toBePinnedPost = try? Importer.shared.decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                
                guard try toBePinnedPost.verified() else  {
#if DEBUG
                    L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
#endif
                    throw ImportErrors.InvalidSignature
                }
                
                
                let toBePinnedPostEvent = Event.saveEvent(event: toBePinnedPost, relays: relays, context: bgContext)
                FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
                    NeedsUpdateInfo(event: toBePinnedPostEvent)
                )
                Event.updateRelays(toBePinnedPost.id, relays: relays, context: bgContext)
            }
        }
    }
}
