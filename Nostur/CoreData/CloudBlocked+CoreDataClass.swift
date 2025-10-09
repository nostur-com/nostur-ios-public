//
//  CloudBlocked+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/11/2023.
//
//

import Foundation
import CoreData

@objc(CloudBlocked)
public class CloudBlocked: NSManagedObject {

}

@MainActor
func temporaryBlock(pubkey: String, forHours hours:Int, name:String = "", context: NSManagedObjectContext = context()) {
    // remove existing block if any
    if let existing = CloudTask.fetchTask(byType: .blockUntil, andPubkey: pubkey, context: context) {
        context.delete(existing)
    }
    
    // add blockUntil task, until date X hours in the future
    if let unblockDate = Calendar.current.date(byAdding: .hour, value: hours, to: .now) {
        _ = CloudTask.new(ofType: .blockUntil, andValue: pubkey, date: unblockDate, context: context)
        DataProvider.shared().saveToDiskNow(.viewContext)
        AppState.shared.createTimer(fireDate: unblockDate, pubkey: pubkey)
    }
        
    CloudBlocked.addBlock(pubkey: pubkey, fixedName: name)
    AppState.shared.bgAppState.blockedPubkeys.insert(pubkey)
    sendNotification(.blockListUpdated, AppState.shared.bgAppState.blockedPubkeys)
}

@MainActor
func block(pubkey: String, name:String? = "", context: NSManagedObjectContext = context()) {
    // remove existing block if any
    if let existing = CloudTask.fetchTask(byType: .blockUntil, andPubkey: pubkey, context: context) {
        context.delete(existing)
    }
        
    CloudBlocked.addBlock(pubkey: pubkey, fixedName: name)
    AppState.shared.bgAppState.blockedPubkeys.insert(pubkey)
    DataProvider.shared().saveToDiskNow(.viewContext)
    sendNotification(.blockListUpdated, AppState.shared.bgAppState.blockedPubkeys)
}


@MainActor
func unblock(pubkey: String, context: NSManagedObjectContext = context()) {
    // remove existing block if any
    if let existing = CloudTask.fetchTask(byType: .blockUntil, andPubkey: pubkey, context: context) {
        context.delete(existing)
    }
    AppState.shared.bgAppState.blockedPubkeys.remove(pubkey)
    if let blocked = CloudBlocked.fetchBlock(byPubkey: pubkey, context: context) {
        context.delete(blocked)
    }
    DataProvider.shared().saveToDiskNow(.viewContext)
    sendNotification(.blockListUpdated, AppState.shared.bgAppState.blockedPubkeys)
}


@MainActor
func mute(eventId: String, replyToRootId: String?, replyToId: String?) {
    CloudBlocked.addBlock(eventId: eventId, replyToRootId: replyToRootId, replyToId: replyToId)
    AppState.shared.bgAppState.mutedRootIds.formUnion(Set([eventId, replyToRootId ?? eventId, replyToId ?? eventId]))
    DataProvider.shared().saveToDiskNow(.viewContext)
    sendNotification(.muteListUpdated, AppState.shared.bgAppState.mutedRootIds)
}
