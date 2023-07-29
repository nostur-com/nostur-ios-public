//
//  Messages.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation

// Message ready to be sent, with envelope  EVENT/REQ/CLOSE
struct ClientMessage {
    enum type {
        case EVENT
        case REQ
        case CLOSE
    }
    
    var onlyForNWCRelay:Bool = false
    var onlyForNCRelay:Bool = false
    var type:ClientMessage.type = .EVENT
    var message:String
    
    static func close(subscriptionId:String) -> String {
        return "[\"CLOSE\", \"\(subscriptionId)\"]"
    }
    
    static func event(event:NEvent) -> String {
        return "[\"EVENT\",\(event.eventJson())]"
    }
}

/// REQ messages for requesting with filters
///
/// TODO: This struct has gotten out of hand, was supposed to be temporary to just try things
/// with a few messages, now its still used for every message..
public struct RequestMessage {
    // TODO: make proper request filter class
    
    static func getArticle(pubkey: String, kind:Int, definition:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "ARTICLE-"+UUID().uuidString)", {"#d": ["\(definition)"], "authors": ["\(pubkey)"], "kinds": [\(kind)], "limit": 11}]
"""
    }
    
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
["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#t": ["\(hashtag)"], "limit": \(limit), "kinds": \(JSON.shared.toString(kinds)) }]
"""
    }
    
                
    
    // Get all events where [pubkeys] are mentioned (in p tag)
    static func getMentions(pubkeys:[String], kinds:[Int] = [1,4,7,9735,9802,30023], limit:Int = 500, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#p": \(JSON.shared.toString(pubkeys)), "since": \(since.timestamp), "kinds": \(JSON.shared.toString(kinds)), "limit": \(limit) }]
    """
        }
        else if let until {
            return """
    ["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#p": \(JSON.shared.toString(pubkeys)), "until": \(until.timestamp), "kinds": \(JSON.shared.toString(kinds)), "limit": \(limit) }]
    """
        }
        return """
["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"#p": \(JSON.shared.toString(pubkeys)), "limit": \(limit), "kinds": \(JSON.shared.toString(kinds)) }]
"""
    }
    
    
    // FETCH A SINGLE EVENT
    static func getEvent(id:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "S-" + UUID().uuidString)", {"ids": ["\(id)"], "limit": 1}]
"""
    }
    
    static func getEvents(ids:[String], limit:Int = 500, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "SS-" + UUID().uuidString)", {"ids": \(JSON.shared.toString(ids)), "limit": \(limit)}]
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
["REQ", "\(subscriptionId ?? "ER-"+UUID().uuidString)", {"ids": ["\(id)"]}, {"#e": ["\(id)"]}]
"""
    }
    
    
    // For fetching events posted by people you follow
    // or reactions by others reacting to the people you follow
    static func getFollowingEvents(pubkeys:[String], limit:Int = 5000, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        let sub = subscriptionId ?? ("F-"+UUID().uuidString)
        let pubs = fasterShort(pubkeys)
        if let since {
            return """
["REQ", "\(sub)", {"authors": \(pubs), "kinds": [1,5,6,9802,30023], "since": \(since.timestamp)}]
"""
        }
        else if let until {
            return """
["REQ", "\(sub)", {"authors": \(pubs), "kinds": [1,5,6,9802,30023], "until": \(until.timestamp)}]
"""
        }
        return """
["REQ", "\(sub)", {"authors": \(pubs), "kinds": [1,5,6,9802,30023], "limit": \(limit)}]
"""
    }
    // Same as above but pubkeys already in string
    static func getFollowingEvents(pubkeysString:String, limit:Int = 5000, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        let sub = subscriptionId ?? ("F-"+UUID().uuidString)
        if let since {
            return """
["REQ", "\(sub)", {"authors": \(pubkeysString), "kinds": [1,5,6,9802,30023], "since": \(since.timestamp), "limit": \(limit)}]
"""
        }
        else if let until {
            return """
["REQ", "\(sub)", {"authors": \(pubkeysString), "kinds": [1,5,6,9802,30023], "until": \(until.timestamp), "limit": \(limit)}]
"""
        }
        return """
["REQ", "\(sub)", {"authors": \(pubkeysString), "kinds": [1,5,6,9802,30023], "limit": \(limit)}]
"""
    }
    
    // For fetching any "global" feed events on a relay
    static func getGlobalFeedEvents(limit:Int = 5000, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        let sub = subscriptionId ?? ("G-"+UUID().uuidString)
        if let since {
            return """
["REQ", "\(sub)", {"kinds": [1,5,6,9802,30023], "since": \(since.timestamp)}]
"""
        }
        else if let until {
            return """
["REQ", "\(sub)", {"kinds": [1,5,6,9802,30023], "until": \(until.timestamp)}]
"""
        }
        return """
["REQ", "\(sub)", {"kinds": [1,5,6,9802,30023], "limit": \(limit)}]
"""
    }
    
    // Fetch anything that references given event ids in tags (1=REPLIES, 6=REPOSTS, 7=REACTIONS, 9735=ZAPS)
    // For when you have event(s) and you want to count replies, reposts, reactions, zaps.
    static func getEventReferences(ids:[String], limit:Int = 5000, subscriptionId:String? = nil, kinds:[Int]? = nil, since:NTimestamp? = nil) -> String {
        let kindsJsonArr = JSON.shared.toString(kinds ?? [1,6,7,9735])
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? ("REF-"+UUID().uuidString))", {"#e": \(JSON.shared.toString(ids)), "kinds":\(kindsJsonArr), "limit": \(limit), "since": \(since.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? ("REF-"+UUID().uuidString))", {"#e": \(JSON.shared.toString(ids)), "kinds":\(kindsJsonArr), "limit": \(limit)}]
"""
    }
    
    // Same as getEventReferences() but for a single Paramaterized Replacable Event
    static func getPREventReferences(aTag:String, limit:Int = 5000, subscriptionId:String? = nil, kinds:[Int]? = nil, since:NTimestamp? = nil) -> String {
        let kindsJsonArr = JSON.shared.toString(kinds ?? [1,6,7,9735])
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? ("REF-A-"+UUID().uuidString))", {"#a": ["\(aTag)"], "kinds":\(kindsJsonArr), "limit": \(limit), "since": \(since.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? ("REF-A-"+UUID().uuidString))", {"#a": ["\(aTag)"], "kinds":\(kindsJsonArr), "limit": \(limit)}]
"""
    }
    
    
    // Fetch anything in the tags (only e -> "ids" and p -> "authors" kind=0  (for now))
    // For when you have 1 event, and want to fetch, reply to, mentions, contacts
    static func getTags(_ tags:[NostrTag], limit:Int = 500, subscriptionId:String? = nil) -> String? {
        let ids = tags.filter { $0.type == "e" }.map { $0.id }
        let authors = tags.filter { $0.type == "p" }.map { $0.pubkey }
        
        // TODO: UGH clean up this if then mess
        if (!ids.isEmpty && !authors.isEmpty) {
            return """
    ["REQ", "\(subscriptionId ?? ("RELATED-"+UUID().uuidString))", {"ids": \(JSON.shared.toString(ids))}, {"authors": \(JSON.shared.toString(authors)), "kinds": [0], "limit": \(limit)}]
    """
        }
        else if (!ids.isEmpty) {
            return """
    ["REQ", "\(subscriptionId ?? ("RELATED-"+UUID().uuidString))", {"ids": \(JSON.shared.toString(ids))}]
    """
        }
        else if (!authors.isEmpty) {
            return """
    ["REQ", "\(subscriptionId ?? ("RELATED-"+UUID().uuidString))", {"authors": \(JSON.shared.toString(authors)), "kinds": [0], "limit": \(limit)}]
    """
        }
        return nil
    }
    
    
    static func getLastSeen(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "LAST-" + UUID().uuidString)", {"authors": ["\(pubkey)"], "limit": 1}]
"""
    }
    
    // Fetch anything in the tags (only e -> "ids" and p -> "authors" kind=0  (for now))
    // For when you have 1 event, and want to fetch, reply to, mentions, contacts
    static func getFastTags(_ tags:[(String, String, String?, String?)], limit:Int = 500, subscriptionId:String? = nil) -> String? {
        let ids = tags.filter { $0.0 == "e" }.map { $0.1 }
        let authors = tags.filter { $0.0 == "p" }.map { $0.1 }
        
        // TODO: UGH clean up this if then mess
        if (!ids.isEmpty && !authors.isEmpty) {
            return """
    ["REQ", "\(subscriptionId ?? ("RELATED-"+UUID().uuidString))", {"ids": \(JSON.shared.toString(ids))}, {"authors": \(JSON.shared.toString(authors)), "kinds": [0], "limit": \(limit)}]
    """
        }
        else if (!ids.isEmpty) {
            return """
    ["REQ", "\(subscriptionId ?? ("RELATED-"+UUID().uuidString))", {"ids": \(JSON.shared.toString(ids))}]
    """
        }
        else if (!authors.isEmpty) {
            return """
    ["REQ", "\(subscriptionId ?? ("RELATED-"+UUID().uuidString))", {"authors": \(JSON.shared.toString(authors)), "kinds": [0], "limit": \(limit)}]
    """
        }
        return nil
    }
    
    
    static func getAuthorContactsList(pubkey:String, limit:Int = 1, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "AC-" + UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [3], "limit": \(limit)}]
"""
    }
    
    static func getAuthorContactsLists(pubkeys:[String], limit:Int = 999, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "ACLS-" + UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [3], "limit": \(limit)}]
"""
    }
    
    static func getFollowers(pubkey:String, since:NTimestamp? = nil, subscriptionId:String? = nil) -> String {
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? "FOLL-" + UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [3], "since": \(since.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? "FOLL-" + UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [3]}]
"""
    }
    
    static func getAuthorKind1(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "A1-" + UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getAuthorNotes(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "AN-" + UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [1,6,9802,30023], "limit": \(limit)}]
"""
    }
    
    static func getAuthorNotesUntil(pubkey:String, until:NTimestamp, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "ANU-" + UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [1,6,9802,30023], "until": \(until.timestamp), "limit": \(limit)}]
"""
    }
    
    static func getAuthorReactions(pubkey:String, limit:Int = 100, until:NTimestamp? = nil, subscriptionId:String? = nil) -> String {
        if let until {
            return """
    ["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [7], "limit": \(limit), "until": \(until.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [7], "limit": \(limit)}]
"""
    }
    
    static func getAuthorZaps(pubkey:String, limit:Int = 5000, until:NTimestamp? = nil, since:NTimestamp? = nil, subscriptionId:String? = nil) -> String {
        if let since {
            return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [9735], "limit": \(limit), "since": \(since.timestamp)}]
"""
        }
        else if let until {
            return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [9735], "limit": \(limit), "until": \(until.timestamp)}]
"""
        }
        else {
            return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [9735], "limit": \(limit)}]
"""
        }
    }
    
    static func getNWCInfo(walletPubkey:String, limit:Int = 1, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(walletPubkey)"], "kinds": [13194], "limit": \(limit)}]
"""
    }
    
    static func getNWCResponses(pubkey:String, walletPubkey:String, limit:Int? = nil, subscriptionId:String? = nil) -> String {
        if let limit {
            return """
    ["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(walletPubkey)"], "#p": ["\(pubkey)"], "kinds": [23195], "limit": \(limit)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(walletPubkey)"], "#p": ["\(pubkey)"], "kinds": [23195]}]
"""
    }
    
    static func getNCResponses(pubkey:String, bunkerPubkey:String, limit:Int? = nil, subscriptionId:String? = nil) -> String {
        if let limit {
            return """
    ["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(bunkerPubkey)"], "#p": ["\(pubkey)"], "kinds": [24133], "limit": \(limit)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(bunkerPubkey)"], "#p": ["\(pubkey)"], "kinds": [24133]}]
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
    
    static func getRelays(pubkeys:[String], subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [3,10002] }]
"""
    }
    
    static func getAuthorsNotes(pubkeys:[String], limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getUserMetadata(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? "UM-" + UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0], "limit": 1}]
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
        let kindsJsonArr = JSON.shared.toString(kinds ?? [0,3,30008,10002])
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": \(kindsJsonArr), "limit": 20}]
"""
    }
    
    static func getUserMetadata(pubkeys:[String], limit:Int? = nil, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? "UM-" + UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [0], "since": \(since.timestamp)}]
    """
        }
        else if let until {
            return """
    ["REQ", "\(subscriptionId ?? "UM-" + UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [0], "until": \(until.timestamp)}]
    """
        }
        
        let limit = limit ?? (pubkeys.count + 20) // add 20 in case of multiple setMetadata's for a pubkey maybe?? not sure
        return """
["REQ", "\(subscriptionId ?? "UM-" + UUID().uuidString)", {"authors": \(fasterShort(pubkeys)), "kinds": [0], "limit": \(limit)}]
"""
    }
}


struct EventMessageBuilder {
    
    static func makeRepost(original: Event) -> NEvent {
        var repost = NEvent(content: "#[0]")
        repost.tags.append(NostrTag(["e", original.id, "", "mention"]))
        repost.tags.append(NostrTag(["p", original.pubkey]))
        repost.kind = .repost
        return repost
    }
    
    static func makeReactionEvent(reactingTo: Event) -> NEvent {
        var tags = reactingTo.tags().filter { $0.type == "e" || $0.type == "p" }
        tags.append(NostrTag(["e", reactingTo.id]))
        tags.append(NostrTag(["p", reactingTo.pubkey]))
        
        var reactionEvent = NEvent(content: "+")
        reactionEvent.kind = .reaction
        reactionEvent.tags = tags
        
        return reactionEvent
    }
    
    static func makeReactionEvent(reactingTo: NEvent) -> NEvent {
        var tags = reactingTo.tags.filter { $0.type == "e" || $0.type == "p" }
        tags.append(NostrTag(["e", reactingTo.id]))
        tags.append(NostrTag(["p", reactingTo.publicKey]))
        
        var reactionEvent = NEvent(content: "+")
        reactionEvent.kind = .reaction
        reactionEvent.tags = tags
        
        return reactionEvent
    }
    
    static func makeDeleteEvent(eventId: String) -> NEvent {
        var event = NEvent(content: "")
        event.kind = .delete
        event.tags = [
            NostrTag(["e", eventId]),
        ]
        return event
    }
    
    static func makeReportEvent(pubkey:String, eventId:String, type:ReportType, note:String = "", includeProfile:Bool = false) -> NEvent {
        var event = NEvent(content: note)
        event.kind = .report
        event.tags = [
            NostrTag(["e", eventId, type.rawValue]),
            includeProfile ? NostrTag(["p", pubkey, type.rawValue]) : NostrTag(["p", pubkey])
        ]
        return event
    }
    
    static func makeReportContact(pubkey:String, type:ReportType, note:String = "") -> NEvent {
        var event = NEvent(content: note)
        event.kind = .report
        event.tags = [NostrTag(["p", pubkey, type.rawValue])]
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


// Short-hand usage example:

//    req(RM.getMentions(
//        pubkeys: [pubkey],
//        kinds: [1],
//        limit: 500,
//        since: 0
//    ))
func req(_ rm:String, activeSubscriptionId:String? = nil, relays:Set<Relay> = []) {
    SocketPool.shared.sendMessage(
        ClientMessage(onlyForNWCRelay: activeSubscriptionId == "NWC", onlyForNCRelay: activeSubscriptionId == "NC", type: .REQ, message: rm),
        subscriptionId: activeSubscriptionId,
        relays: relays
    )
}

func reqP(_ rm:String, activeSubscriptionId:String? = nil, relays:Set<Relay> = []) {
    SocketPool.shared.sendMessageAfterPing(
        ClientMessage(onlyForNWCRelay: activeSubscriptionId == "NWC", onlyForNCRelay: activeSubscriptionId == "NC", type: .REQ, message: rm),
        subscriptionId: activeSubscriptionId,
        relays: relays
    )
}

public typealias RM = RequestMessage


class JSON {
    static let shared = JSON()
    private var encoder = JSONEncoder()
    
    func toString(_ ints:[Int]) -> String {
        do {
            let jsonData = try encoder.encode(ints)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString // Output: "[1,7,9735,4,9802]"
            }
            return "[]"
        } catch {
            return "[]"
        }
    }
    
    func toString(_ pubkeys:[String]) -> String {
        do {
            let jsonData = try encoder.encode(pubkeys)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString // Output: "[1,7,9735,4,9802]"
            }
            return "[]"
        } catch {
            return "[]"
        }
    }
}


// For decoding relays in kind 3 .content
struct Kind3Relay: Decodable {
    let url: String
    let readWrite: ReadWrite
    
    struct ReadWrite: Decodable {
        let write: Bool?
        let read: Bool?
    }
}

struct Kind3Relays: Decodable {
    let relays: [Kind3Relay]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let serverDict = try container.decode([String: Kind3Relay.ReadWrite].self)

        self.relays = serverDict.map { Kind3Relay(url: $0.key, readWrite: $0.value) }
    }
}
