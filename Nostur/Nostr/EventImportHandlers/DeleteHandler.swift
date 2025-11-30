//
//  DeleteHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleDelete(nEvent: NEvent, context: NSManagedObjectContext) {
    guard nEvent.kind == .delete else { return }
    
    let eventIdsToDelete = nEvent.eTags()
    // TODO: Also do aTags
    
    let eventIdsToDeleteReq = NSFetchRequest<Event>(entityName: "Event")
    
    // Only same author (pubkey) can delete // TODO: Should just allow all kinds?
    eventIdsToDeleteReq.predicate = NSPredicate(format: "kind IN {1,1111,1222,1244,6,20,9802,10001,10601,30023,34235} AND pubkey = %@ AND id IN %@ AND deletedById = nil", nEvent.publicKey, eventIdsToDelete)
    eventIdsToDeleteReq.sortDescriptors = []
    if let eventsToDelete = try? context.fetch(eventIdsToDeleteReq) {
        for eventToDelete in eventsToDelete {
            eventToDelete.deletedById = nEvent.id
            ViewUpdates.shared.postDeleted.send((toDeleteId: eventToDelete.id, deletedById: nEvent.id))
        }
    }
}
