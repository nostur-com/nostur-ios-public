//
//  PersistentNotification+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//
//

import Foundation
import CoreData

public typealias PNType = PersistentNotification.PersistentNotificationType

@objc(PersistentNotification)
public class PersistentNotification: NSManagedObject {
    
    public enum PersistentNotificationType: String {
        case none = "NONE"
        case newFollowers = "NEW_FOLLOWERS"
        case failedZap = "FAILED_ZAP"
        case failedZaps = "FAILED_ZAPS" // Error
        case failedZapsTimeout = "FAILED_ZAPS_TIMEOUT" // Timeout
        case failedLightningInvoice = "FAILED_LIGHTNING_INVOICE"
        case newPosts = "NEW_POSTS"
    }
    
    static func create(pubkey:String, followers:[String], context:NSManagedObjectContext) -> PersistentNotification {
        let newFollowersNotification = PersistentNotification(context: context)
        newFollowersNotification.id = UUID()
        newFollowersNotification.createdAt = .now
        newFollowersNotification.pubkey = pubkey
        newFollowersNotification.type = .newFollowers
        newFollowersNotification.content = followers.joined(separator: ",")
        return newFollowersNotification
    }
    
    static func createFailedNWCZap(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedZap
        failedZapNotification.content = message
        return failedZapNotification
    }
    
    static func createFailedLightningInvoice(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedLightningInvoice
        failedZapNotification.content = message
        return failedZapNotification
    }
    
    static func createFailedNWCZaps(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedZaps
        failedZapNotification.content = message
        return failedZapNotification
    }
    
    static func createTimeoutNWCZaps(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedZaps
        failedZapNotification.content = message
        return failedZapNotification
    }
    
    // pubkey is for the account the notification is for (not always relevant, but its not the pubkey of a contact in the notification)
    static func createNewPostsNotification(pubkey: String, context: NSManagedObjectContext = context(), contacts:[ContactInfo]) -> PersistentNotification {
  
        let newPostNotification = PersistentNotification(context: context)
        newPostNotification.id = UUID()
        newPostNotification.createdAt = .now
        newPostNotification.pubkey = pubkey
        newPostNotification.type = .newPosts
        if let contactsData = try? JSONEncoder().encode(contacts), let contactsJson = String(data: contactsData, encoding: .utf8) {
            newPostNotification.content = contactsJson
        }
        return newPostNotification
    }
    
    static func fetchUnreadNewPostNotifications(accountPubkey: String) -> [PersistentNotification] {
        let fr = PersistentNotification.fetchRequest()
        fr.predicate = NSPredicate(format: "pubkey = %@ AND readAt = nil AND type_ = %@", accountPubkey, PersistentNotificationType.newPosts.rawValue)
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        guard let existing = (try? context().fetch(fr)) else { return [] }
        return existing
    }
}
