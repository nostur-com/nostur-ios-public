//
//  OfflinePosts.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/10/2025.
//

import SwiftUI
import CoreData

class OfflinePosts {
    
    
    static func checkForOfflinePosts(_ maxAgo: TimeInterval = 259_200) { // 3 days
        DispatchQueue.main.async {
            guard ConnectionPool.shared.anyConnected else { return }
            let pubkey = AccountsState.shared.activeAccountPublicKey
            
            bg().perform {
                let xDaysAgo = Date.now.addingTimeInterval(-(maxAgo))
                
                let r1 = Event.fetchRequest()
                // X days ago, from our pubkey, only kinds that we can create+send
                r1.predicate = NSPredicate(format:
                                            "created_at > %i " +
                                            "AND pubkey = %@ " +
                                            "AND kind IN {0,1,1111,1222,1244,3,4,5,6,7,20,9802,34235} " +
                                            "AND relays = \"\"" +
                                            "AND NOT flags IN {\"nsecbunker_unsigned\",\"awaiting_send\",\"draft\"}" +
                                            "AND sig != nil",
                                            Int64(xDaysAgo.timeIntervalSince1970),
                                            pubkey)
                r1.fetchLimit = 100 // sanity
                r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
                
                if let offlinePosts = try? bg().fetch(r1) {
                    guard !offlinePosts.isEmpty else { return }
                    for offlinePost in offlinePosts {
                        let nEvent = offlinePost.toNEvent()

                        // don't publish restricted events
                        guard !nEvent.isRestricted else { continue }
                        // make sure that event is older than 15 seconds to prevent interfering with undo timer
                        guard offlinePost.created_at < Int64(Date.now.timeIntervalSince1970 - 15) else { continue }
#if DEBUG
                        L.og.debug("Publishing offline post: \(offlinePost.id)")
#endif
                        DispatchQueue.main.async {
                            Unpublisher.shared.publishNow(nEvent)
                        }
                    }
                }
            }
        }
    }
}
