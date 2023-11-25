//
//  CloudTask+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/11/2023.
//
//

import Foundation
import CoreData

@objc(CloudTask)
public class CloudTask: NSManagedObject {

}

func block(pubkey: String, forHours hours:Int, name:String = "", context: NSManagedObjectContext = context()) {
    // remove existing block if any
    if let existing = CloudTask.fetchTask(byType: .blockUntil, andPubkey: pubkey, context: context) {
        context.delete(existing)
    }
    
    // add blockUntil task, until date X hours in the future
    if let unblockDate = Calendar.current.date(byAdding: .hour, value: hours, to: .now) {
        _ = CloudTask.new(ofType: .blockUntil, andValue: pubkey, date: unblockDate, context: context)
        save(context: context)
        NRState.shared.createTimer(fireDate: unblockDate, pubkey: pubkey)
    }
        
    CloudBlocked.addBlock(pubkey: pubkey, fixedName: name)
    sendNotification(.blockListUpdated, CloudBlocked.blockedPubkeys())
}
