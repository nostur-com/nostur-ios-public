//
//  CloudTask+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/11/2023.
//
//

import Foundation
import CoreData


extension CloudTask {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudTask> {
        return NSFetchRequest<CloudTask>(entityName: "CloudTask")
    }

    @NSManaged public var createdAt_: Date?
    
    // type of task (use .type/CloudTaskType)
    @NSManaged public var type_: String?
    
    // when to remove task
    @NSManaged public var date_: Date?
    
    // a value needed by the task, post id / pubkey / whatever
    @NSManaged public var value_: String?
    
    // account the task should be restricted to. Blocks are app wide, but other tasks could be limited to an account
    @NSManaged public var accountPubkey_: String?
    
    static func fetchTask(byType type:CloudTaskType, andPubkey pubkey:String, andAccountPubkey accountPubkey: String? = nil, context: NSManagedObjectContext = context()) -> CloudTask? {
        let fr = CloudTask.fetchRequest()
        if let accountPubkey {
            fr.predicate = NSPredicate(format: "type_ == %@ AND value_ == %@ AND accountPubkey_ == %@", type.rawValue, pubkey, accountPubkey)
        }
        else {
            fr.predicate = NSPredicate(format: "type_ == %@ AND value_ == %@", type.rawValue, pubkey)
        }
        fr.fetchLimit = 1
        return try? context.fetch(fr).first
    }
    
    static func fetchAll(byType type:CloudTaskType? = nil, andAccountPubkey accountPubkey: String? = nil, context: NSManagedObjectContext = context()) -> [CloudTask] {
        let fr = CloudTask.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudTask.createdAt_, ascending: false)]
        if let type = type, let accountPubkey = accountPubkey {
            fr.predicate = NSPredicate(format: "type_ == %@ AND accountPubkey_ == %@", type.rawValue, accountPubkey)
        }
        else if let type = type {
            fr.predicate = NSPredicate(format: "type_ == %@", type.rawValue)
        }
        else if let accountPubkey = accountPubkey {
            fr.predicate = NSPredicate(format: "accountPubkey_ == %@", accountPubkey)
        }
        return (try? context.fetch(fr)) ?? []
    }

    static func new(ofType type: CloudTaskType, andValue value: String, date: Date, context: NSManagedObjectContext = context()) -> CloudTask {
        let task = CloudTask(context: context)
        task.createdAt = .now
        task.type = type
        task.date = date
        task.value = value
        return task
    }
}

extension CloudTask : Identifiable {
    
    public enum CloudTaskType: String {
        case notifyOnPosts = "NOTIFY_ON_POSTS"
        case blockUntil = "BLOCK_UNTIL"
        case unknown = "UNKNOWN"
    }
    
    public var createdAt: Date {
        get { createdAt_ ?? .distantPast }
        set { createdAt_ = newValue }
    }
    public var type: CloudTaskType {
        get { CloudTaskType(rawValue: (type_ ?? "UNKNOWN")) ?? .unknown }
        set { type_ = newValue.rawValue }
    }
    public var date: Date {
        get { date_ ?? .distantPast }
        set { date_ = newValue }
    }
    public var value: String {
        get {
            value_ ?? ""
        }
        set {
            value_ = newValue
        }
    }
}


