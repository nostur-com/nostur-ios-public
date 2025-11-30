//
//  ReplacableEventHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleReplacableEvent(nEvent: NEvent, context: NSManagedObjectContext) {
    guard (nEvent.kind.id >= 10000 && nEvent.kind.id < 20000) else { return }
    
    // delete older events
    let r = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
    r.predicate = NSPredicate(format: "kind == %d AND pubkey == %@ AND created_at < %d", nEvent.kind.id, nEvent.publicKey, nEvent.createdAt.timestamp)
    let batchDelete = NSBatchDeleteRequest(fetchRequest: r)
    batchDelete.resultType = .resultTypeCount
    
    do {
        _ = try context.execute(batchDelete) as! NSBatchDeleteResult
    } catch {
        L.og.error("🔴🔴 Failed to delete older replaceable events for \(nEvent.id)")
    }
}
