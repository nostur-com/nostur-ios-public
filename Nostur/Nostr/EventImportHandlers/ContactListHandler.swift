//
//  ContactListHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData


func handleContactList(_ event: NEvent, subscriptionId: String?) {
    if event.kind == .contactList {
        if event.publicKey == EXPLORER_PUBKEY {
            // use explorer account p's for "Explorer" feed
            let pTags = event.pTags()
            Task { @MainActor in
                AppState.shared.rawExplorePubkeys = Set(pTags)
            }
        }
        if event.publicKey == AccountsState.shared.activeAccountPublicKey { // To enable Follow button we need to have received a contact list
            DispatchQueue.main.async {
                FollowingGuardian.shared.didReceiveContactListThisSession = true
#if DEBUG
                L.og.info("🙂🙂 FollowingGuardian.didReceiveContactListThisSession")
#endif
            }
        }

        
        // Send new following list notification, but skip if it is for building the Web of Trust
        if let subId = subscriptionId, subId.prefix(7) != "WoTFol-" {
            let n = event
            DispatchQueue.main.async {
                sendNotification(.newFollowingListFromRelay, n)
            }
        }
    }
}

func handleContactList(nEvent: NEvent, context: NSManagedObjectContext) {
    guard nEvent.kind == .contactList else { return }
    // delete older events
    let r = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
    r.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@ AND created_at < %d", nEvent.publicKey, nEvent.createdAt.timestamp)
    let batchDelete = NSBatchDeleteRequest(fetchRequest: r)
    batchDelete.resultType = .resultTypeCount
    
    do {
        _ = try context.execute(batchDelete) as! NSBatchDeleteResult
    } catch {
        L.og.error("🔴🔴 Failed to delete older kind 3 events")
    }
}
