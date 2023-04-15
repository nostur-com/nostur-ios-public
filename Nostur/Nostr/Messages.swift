//
//  Messages.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import SwiftyJSON
// TODO: Remove SwiftyJSON code so we can remove package

// Message ready to sent, with envelope  EVENT/REQ/CLOSE
struct ClientMessage {
    enum type {
        case EVENT
        case REQ
        case CLOSE
    }
    
    var type:ClientMessage.type = .EVENT
    var message:String
    
    static func close(subscriptionId:String) -> String {
        return "[\"CLOSE\", \"\(subscriptionId)\"]"
    }
    
    static func event(event:NEvent) -> String {
        return "[\"EVENT\",\(event.eventJson())]"
    }
}

// Messages received from relay EVENT/EOSE/NOTICE
struct RelayMessage {
    
    enum type:String {
        case EVENT
        case NOTICE
        case EOSE
        case OK
        case AUTH
    }
    
    enum error:Error {
        case FAILED_TO_PARSE // Failed to parse raw websocket
        case UNKNOWN_MESSAGE_TYPE // NOT EVENT, NOTICE or EOSE
        case FAILED_TO_PARSE_EVENT // Could parse raw websocket but not event
    }
    
    var relay:String
    var type:RelayMessage.type?
    var message:String
    var subscriptionId:String?
    var event:NEvent?
    
    var id:String?
    var success:Bool?
    
    static func parseRelayMessage(text:String, relay:String, skipValidation:Bool = false) throws -> RelayMessage {
        guard let dataFromString = text.data(using: .utf8, allowLossyConversion: false) else {
            throw error.FAILED_TO_PARSE
        }
        
        guard text.prefix(7) != ###"["EOSE""### else {
            let decoder = JSONDecoder()
            guard let eose = try? decoder.decode(NMessage.self, from: dataFromString) else {
                throw error.FAILED_TO_PARSE
            }
            return RelayMessage(relay:relay, type: .EOSE, message: text, subscriptionId: eose.subscription)
        }
        
        guard text.prefix(7) != ###"["AUTH""### else {
            return RelayMessage(relay:relay, type: .AUTH, message: text)
        }
        
        guard text.prefix(9) != ###"["NOTICE""### else {
            return RelayMessage(relay:relay, type: .NOTICE, message: text)
        }
        
        guard text.prefix(5) != ###"["OK""### else {
            let decoder = JSONDecoder()
            guard let result = try? decoder.decode(CommandResult.self, from: dataFromString) else {
                throw error.FAILED_TO_PARSE
            }
            return RelayMessage(relay:relay, type: .OK, message: text, id:result.id, success:result.success)
        }
        
        guard text.prefix(8) == ###"["EVENT""### else {
            throw error.UNKNOWN_MESSAGE_TYPE
        }
        
        let decoder = JSONDecoder()
        guard let relayMessage = try? decoder.decode(NMessage.self, from: dataFromString) else {
            throw error.FAILED_TO_PARSE
        }
//        guard let json = try? JSON(data: dataFromString) else {
//            throw error.FAILED_TO_PARSE
//        }
        
//        let decoder = JSONDecoder()
//        guard let event = try? decoder.decode(NEvent.self, from: Data(json[2].rawData())) else {
//            throw error.FAILED_TO_PARSE_EVENT
//        }
        guard let nEvent = relayMessage.event else {
            throw "WHERES THE PAYLOAD BRO"
        }
        
        guard try skipValidation || nEvent.verified() else {
            print("🟣\(relayMessage)")
            throw "🔴🔴🔴 NO VALID SIG 🔴🔴🔴 "
        }
        
        return RelayMessage(relay:relay, type: .EVENT, message: text, subscriptionId: relayMessage.subscription, event: nEvent)
    }
}

// REQ messages for requesting with filters
struct RequestMessage {
    
    static func getBadgeDefinitions(filters:[(Int64, String, String)], subscriptionId:String? = nil) -> String {
        // (kinds, badgeCode, author)
        let stringFilters = filters.map {
            "{ \"#d\": [\"\($0.1)\"], \"authors\": [\"\($0.2)\"], \"kinds\": [\($0.0)] }"
        }
        
        return """
["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", \(stringFilters.joined(separator: ",") )]
"""
    }
    
    static func getBadgesCreatedAndAwarded(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [30009,8], "limit": 500}]
"""
    }
    // Get all events where [pubkeys] are mentioned (in p tag)
    static func getHashtag(hashtag:String, kinds:[Int] = [1], limit:Int = 500,  subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#t": ["\(hashtag)"], "limit": \(limit), "kinds": \(JSON(kinds).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]") }]
"""
    }
    
                
    
    // Get all events where [pubkeys] are mentioned (in p tag)
    static func getMentions(pubkeys:[String], kinds:[Int] = [1,7,9735,4], limit:Int = 500, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        
        if since != nil {
            return """
    ["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#p": \(JSON(pubkeys).rawString(.utf8, options: .init(rawValue: 0))!), "since": \(since!.timestamp), "kinds": \(JSON(kinds).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]") }]
    """
        }
        else if until != nil {
            return """
    ["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#p": \(JSON(pubkeys).rawString(.utf8, options: .init(rawValue: 0))!), "until": \(until!.timestamp), "kinds": \(JSON(kinds).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]") }]
    """
        }
        return """
["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#p": \(JSON(pubkeys).rawString(.utf8, options: .init(rawValue: 0))!), "limit": \(limit), "kinds": \(JSON(kinds).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]") }]
"""
    }
    
    
    // FETCH A SINGLE EVENT
    static func getEvent(id:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"ids": ["\(id)"], "limit": 1}]
"""
    }
    
    static func getEvents(ids:[String], limit:Int = 500, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"ids": \(JSON(ids).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]"), "limit": \(limit)}]
"""
    }
    // FETCH A SINGLE EVENT AND REFERENCES
    static func getBadgesReceived(_ pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"kinds": [8]}, {"#p": ["\(pubkey)"]}]
"""
    }
    
    // FETCH A SINGLE EVENT AND REFERENCES
    static func getEventAndReferences(id:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"ids": ["\(id)"]}, {"#e": ["\(id)"]}]
"""
    }
    
    
    // For fetching events posted by people you follow
    // or reactions by others reacting to the people you follow
    static func getFollowingEvents(pubkeys:[String], limit:Int = 5000, subscriptionId:String? = nil, since:NTimestamp? = nil) -> String {
        let sub = subscriptionId ?? ("TL-"+UUID().uuidString)
        let pubs = fasterShort(pubkeys)
        if since != nil {
            return """
["REQ", "\(sub)", {"authors": \(pubs), "kinds": [1,5,6], "since": \(since!.timestamp)}]
"""
        }
        return """
["REQ", "\(sub)", {"authors": \(pubs), "kinds": [1,5,6], "limit": \(limit)}]
"""
    }
    // Same as above but pubkeys already in string
    static func getFollowingEvents(pubkeysString:String, limit:Int = 5000, subscriptionId:String? = nil, since:NTimestamp? = nil) -> String {
        let sub = subscriptionId ?? ("TL-"+UUID().uuidString)
        if since != nil {
            return """
["REQ", "\(sub)", {"authors": \(pubkeysString), "kinds": [1,5,6], "since": \(since!.timestamp)}]
"""
        }
        return """
["REQ", "\(sub)", {"authors": \(pubkeysString), "kinds": [1,5,6], "limit": \(limit)}]
"""
    }
    
    
    // For fetching events posted by people you follow
    // or reactions by others reacting to the people you follow
    // HMMM #P FILTER NIET HANDIG HIER....
//    static func getFollowingEvents(pubkeys:[String?], limit:Int = 500, subscriptionId:String? = nil, since:NTimestamp? = nil) -> String {
//
//        if since != nil {
//            return """
//    ["REQ", "\(subscriptionId ?? ("TL-"+UUID().uuidString))", {"authors": \(JSON(pubkeys).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]"), "limit": \(limit), "since": \(since!.timestamp)}, {"#p": \(JSON(pubkeys).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]"), "kinds": [0,1,6,7,9735], "limit": \(limit), "since": \(since!.timestamp)}]
//    """
//        }
//        return """
//["REQ", "\(subscriptionId ?? ("TL-"+UUID().uuidString))", {"authors": \(JSON(pubkeys).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]"), "kinds": [0,1,6,7,9735], "limit": \(limit)}]
//"""
//    }
    
    // Fetch anything that references given event ids in tags (1=REPLIES, 6=REPOSTS, 7=REACTIONS, 9735=ZAPS)
    // For when you have event(s) and you want to count replies, reposts, reactions, zaps.
    static func getEventReferences(ids:[String], limit:Int = 5000, subscriptionId:String? = nil, kinds:[Int]? = nil) -> String {
        let kindsJsonArr = kinds != nil ? JSON(kinds!).rawString(.utf8, options: .init(rawValue: 0)) : "[1,6,7,9735]"
        return """
["REQ", "\(subscriptionId ?? ("TL-REF-"+UUID().uuidString))", {"#e": \(JSON(ids).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]"), "kinds":\(kindsJsonArr!), "limit": \(limit)}]
"""
    }
    
    
    // Fetch anything in the tags (only e -> "ids" and p -> "authors" kind=0  (for now))
    // For when you have 1 event, and want to fetch, reply to, mentions, contacts
    static func getTags(_ tags:[NEventTag], limit:Int = 500, subscriptionId:String? = nil) -> String? {
        let ids = tags.filter { $0.type == "e" }.map { $0.id }
        let authors = tags.filter { $0.type == "p" }.map { $0.pubkey }
        
        // TODO: UGH clean up this if then mess
        if (ids.count > 0 && authors.count > 0) {
            return """
    ["REQ", "\(subscriptionId ?? ("TL-TAG-"+UUID().uuidString))", {"ids": \(JSON(ids).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]")}, {"authors": \(JSON(authors).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]"), "kinds": [0], "limit": \(limit)}]
    """
        }
        else if (ids.count > 0) {
            return """
    ["REQ", "\(subscriptionId ?? ("TL-TAG-"+UUID().uuidString))", {"ids": \(JSON(ids).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]")}]
    """
        }
        else if (authors.count > 0) {
            return """
    ["REQ", "\(subscriptionId ?? ("TL-TAG-"+UUID().uuidString))", {"authors": \(JSON(authors).rawString(.utf8, options: .init(rawValue: 0)) ?? "[]"), "kinds": [0], "limit": \(limit)}]
    """
        }
        return nil
    }
    
    
    static func getAuthorContactsList(pubkey:String, limit:Int = 1, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [3], "limit": \(limit)}]
"""
    }
    
    static func getAuthorNotes(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [1,6], "limit": \(limit)}]
"""
    }
    
    static func getAuthorReactions(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [7], "limit": \(limit)}]
"""
    }
    
    static func getAuthorZaps(pubkey:String, limit:Int = 1000, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [9735], "limit": \(limit)}]
"""
    }
    
    static func getAuthorDMs(pubkey:String, limit:Int = 1000, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [4], "limit": \(limit)}, {"authors": ["\(pubkey)"], "kinds": [4], "limit": \(limit)}]
"""
    }
    
    static func getDMConversation(pubkey:String, theirPubkey:String, limit:Int = 1000, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "#p": ["\(theirPubkey)"], "kinds": [4], "limit": \(limit)}, {"authors": ["\(theirPubkey)"], "#p": ["\(pubkey)"], "kinds": [4], "limit": \(limit)}]
"""
    }
    
    static func getAuthorsEvents(pubkeys:[String], limit:Int = 200, subscriptionId:String? = nil, since:NTimestamp? = nil) -> String {
        
        if since != nil {
            return """
    ["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "since": \(since!.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "limit": \(limit)}]
"""
    }
    
    static func getAuthorsNotes(pubkeys:[String], limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getUserMetadata(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0], "limit": 1}]
"""
    }
    
    static func getUserMetadataAndBadges(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0,30008], "limit": 10}]
"""
    }
    
    static func getUserMetadataAndContactList(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0,3], "limit": 20}]
"""
    }
    
    static func getUserProfileKinds(pubkey:String, subscriptionId:String? = nil, kinds:[Int]? = nil) -> String {
        let kindsJsonArr = kinds != nil ? JSON(kinds!).rawString(.utf8, options: .init(rawValue: 0)) : "[0,3,30008,10002]"
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": \(kindsJsonArr!), "limit": 20}]
"""
    }
    
    static func getUserMetadata(pubkeys:[String], limit:Int? = nil, subscriptionId:String? = nil, since:NTimestamp? = nil) -> String {
        
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [0], "since": \(since.timestamp)}]
    """
        }
        
        let limit = limit ?? (pubkeys.count + 20) // add 20 in case of multiple setMetadata's for a pubkey maybe?? not sure
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [0], "limit": \(limit)}]
"""
    }
}


struct EventMessageBuilder {
    
    static func makeRepost(original: Event) -> NEvent {
        var repost = NEvent(content: "#[0]")
        repost.tags.append(NEventTag(type: "e", otherInformation: original.id, "", "mention"))
        repost.tags.append(NEventTag(type: "p", otherInformation: original.pubkey))
        repost.kind = .repost
        return repost
    }
    
    static func makeReactionEvent(reactingTo: Event) -> NEvent {
        var tags = reactingTo.tags().filter { $0.type == "e" || $0.type == "p" }
        tags.append(NEventTag(type: "e", otherInformation: reactingTo.id))
        tags.append(NEventTag(type: "p", otherInformation: reactingTo.pubkey))
        
        var reactionEvent = NEvent(content: "+")
        reactionEvent.kind = .reaction
        reactionEvent.tags = tags
        
        return reactionEvent
    }
    
    static func makeReactionEvent(reactingTo: NEvent) -> NEvent {
        var tags = reactingTo.tags.filter { $0.type == "e" || $0.type == "p" }
        tags.append(NEventTag(type: "e", otherInformation: reactingTo.id))
        tags.append(NEventTag(type: "p", otherInformation: reactingTo.publicKey))
        
        var reactionEvent = NEvent(content: "+")
        reactionEvent.kind = .reaction
        reactionEvent.tags = tags
        
        return reactionEvent
    }
    
    static func makeDeleteEvent(eventId: String) -> NEvent {
        var event = NEvent(content: "")
        event.kind = .delete
        event.tags = [
            NEventTag(type: "e", otherInformation: eventId),
        ]
        return event
    }
    
    static func makeReportEvent(pubkey:String, eventId:String, type:ReportType, note:String = "", includeProfile:Bool = false) -> NEvent {
        var event = NEvent(content: note)
        event.kind = .report
        event.tags = [
            NEventTag(type: "e", otherInformation: [eventId, type.rawValue]),
            includeProfile ? NEventTag(type: "p", otherInformation: [pubkey, type.rawValue]) : NEventTag(type: "p", otherInformation: pubkey)
        ]
        return event
    }
    
    static func makeReportContact(pubkey:String, type:ReportType, note:String = "") -> NEvent {
        var event = NEvent(content: note)
        event.kind = .report
        event.tags = [NEventTag(type: "p", otherInformation: [pubkey, type.rawValue])]
        return event
    }
}

enum ReportType:String {
    case nudity = "nudity"
    case profanity = "profanity"
    case illegal = "illegal"
    case spam = "spam"
    case impersonation = "impersonation"
}

func short(_ pubkeys:[String], prefixLength:Int = 10) -> [String] {
    pubkeys.map { String( "\"" +  $0.prefix(prefixLength) + "\"") }
}

func fasterShort(_ pubkeys:[String], prefixLength:Int = 10) -> String {
    "[" + pubkeys.map {  "\"" +  $0.prefix(prefixLength) + "\"" }.joined(separator: ",") + "]"
}
