//
//  Event+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2023.
//
//

import Foundation
import CoreData
import Compactor


extension Event {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        return NSFetchRequest<Event>(entityName: "Event")
    }
    
    @NSManaged public var content: String?
    @NSManaged public var created_at: Int64
    @NSManaged public var id: String?
    @NSManaged public var kind: Int16
    @NSManaged public var pubkey: String?
    @NSManaged public var sig: String?
    @NSManaged public var tagsSerialized: String?
    
    @NSManaged public var replyToRootId: String?
    @NSManaged public var replyToId: String?
}

extension Event : Identifiable {
    
    var date: Date {
        get {
           Date(timeIntervalSince1970: Double(created_at))
        }
    }
    
    var ago: String {
        get {
            let f = TimeCompactor(ifZero: nil, style: .short, roundSmallToWhole: true)
            return f.string(from: Double(Date.now.timeIntervalSince(date)) as NSNumber)!
        }
    }
    
    var authorKey: String {
        get {
            pubkey != nil ? String(pubkey!.prefix(5)) : "?:?"
        }
    }
    
    var noteText: String {
        get {
            content ?? "(empty note)"
        }
    }
    
    static func textNotes(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.includesPendingChanges = false
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 1 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return request
    }
    
    // GETTER for "setMetaData" Events. !! NOT A SETTER !!
    static func setMetaDataEvents(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 0 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 0")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return request
    }
    
    static func contactListEvents(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 3")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return request
    }
    
    @discardableResult
    static func makePreviews(count: Int) -> [Event] {
        var events = [Event]()
        let viewContext = EventsProvider.preview.container.viewContext
        for index in 0..<count {
            let event = Event(context: viewContext)
            event.pubkey = "pubkey\(index)" //rand from preview keys
            event.id = "id\(index)"
            event.created_at = Int64(Date().timeIntervalSinceNow)
            event.content = "Preview event"
            event.kind = 0
            event.sig = "ddd"
            events.append(event)
        }
        return events
    }
}

/// A struct encapsulating the properties of a Quake.
struct EventProperties: Decodable {

    
    public var content: String?
    public var created_at: Int64
    public var id: String?
    public var kind: Int16
    public var pubkey: String?
    public var sig: String?
    public var tagsSerialized: String?
    
    public var replyToRootId: String?
    public var replyToId: String?
    
    // MARK: Codable
    
    private enum CodingKeys: String, CodingKey {
        case content
        case created_At
        case id
        case kind
        case pubkey
        case sig
        
        // tags?
        case tagsSerialized
        case replyToRootId
        case replyToId
//        case magnitude = "mag"
    }
    
    init(from decoder: Decoder) throws {
        
        self.content = nil
        self.created_at = Int64(Date().timeIntervalSinceNow)
        self.id = nil
        self.kind = 0
        self.pubkey = "111"
        self.sig = "11"
        self.tagsSerialized = nil
        self.replyToRootId = nil
        self.replyToId = nil
        
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        let rawMagnitude = try? values.decode(Float.self, forKey: .magnitude)
//        let rawPlace = try? values.decode(String.self, forKey: .place)
//        let rawTime = try? values.decode(Double.self, forKey: .time)
//        let rawCode = try? values.decode(String.self, forKey: .code)
//
//        // Ignore earthquakes with missing data.
//        guard let magntiude = rawMagnitude,
//              let place = rawPlace,
//              let time = rawTime,
//              let code = rawCode
//        else {
//            let values = "code = \(rawCode?.description ?? "nil"), "
//            + "mag = \(rawMagnitude?.description ?? "nil"), "
//            + "place = \(rawPlace?.description ?? "nil"), "
//            + "time = \(rawTime?.description ?? "nil")"
//
//            let logger = Logger(subsystem: "com.example.apple-samplecode.Earthquakes", category: "parsing")
//            logger.debug("Ignored: \(values)")
//
//            throw QuakeError.missingData
//        }
//
//        self.magnitude = magntiude
//        self.place = place
//        self.time = time
//        self.code = code
    }
    
    // The keys must have the same name as the attributes of the Quake entity.
    var dictionaryValue: [String: Any] {
        [
            "magnitude": 1
        ]
//        [
//            "magnitude": magnitude,
//            "place": place,
//            "time": Date(timeIntervalSince1970: TimeInterval(time) / 1000),
//            "code": code
//        ]
    }
}
