//
//  Messages.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import NostrEssentials

// Message ready to be sent, with envelope  EVENT/REQ/CLOSE
struct ClientMessage {
    enum type {
        case EVENT
        case REQ
        case CLOSE
    }
    
    enum RelayType {
        case READ
        case WRITE
        case SEARCH
    }
    
    var onlyForNWCRelay:Bool = false
    var onlyForNCRelay:Bool = false
    var type:ClientMessage.type = .EVENT
    var message:String
    var relayType:RelayType
    
    static func close(subscriptionId:String) -> String {
        return "[\"CLOSE\", \"\(subscriptionId)\"]"
    }
    
    static func event(event: NEvent) -> String {
        return "[\"EVENT\",\(event.eventJson())]"
    }
    
    static func auth(event: NEvent) -> String {
        return "[\"AUTH\",\(event.eventJson())]"
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
["REQ", "\(subscriptionId ?? ("ARTICLE-"+UUID().uuidString))", {"#d": ["\(definition)"], "authors": ["\(pubkey)"], "kinds": [\(kind)], "limit": 11}]
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
    static func getMentions(pubkeys:[String], kinds:[Int] = [1,4,7,20,9735,9802,30023,34235], limit:Int = 500, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        
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
["REQ", "\(subscriptionId ?? ("S-" + UUID().uuidString))", {"ids": ["\(id)"], "limit": 1}]
"""
    }
    
    static func getEvents(ids:[String], limit:Int = 500, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? ("SS-" + UUID().uuidString))", {"ids": \(JSON.shared.toString(ids)), "limit": \(limit)}]
"""
    }
    // FETCH A SINGLE EVENT AND REFERENCES
    static func getBadgesReceived(_ pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"kinds": [8]}, {"#p": ["\(pubkey)"]}]
"""
    }
    
//    // For fetching any "global" feed events on a relay
//    static func getGlobalFeedEvents(limit: Int = 250, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
//        let sub = subscriptionId ?? ("G-"+UUID().uuidString)
//        if let since {
//            return """
//["REQ", "\(sub)", {"kinds": [1,6,20,9802,30023,34235], "since": \(since.timestamp)}]
//"""
//        }
//        else if let until {
//            return """
//["REQ", "\(sub)", {"kinds": [1,6,20,9802,30023,34235], "until": \(until.timestamp)}]
//"""
//        }
//        return """
//["REQ", "\(sub)", {"kinds": [1,6,20,9802,30023,34235], "limit": \(limit)}]
//"""
//    }
    
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
    
    // Same as getEventReferences() but for a single Parameterized Replaceable Event
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
    
    static func getAddressableEvent(aTag: String, limit:Int = 5000, subscriptionId:String? = nil, kinds:[Int]? = nil, since:NTimestamp? = nil) -> String {
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
["REQ", "\(subscriptionId ?? ("LAST-" + UUID().uuidString))", {"authors": ["\(pubkey)"], "limit": 1}]
"""
    }
    
    // Fetch anything in the tags (only e -> "ids" and p -> "authors" kind=0  (for now))
    // For when you have 1 event, and want to fetch, reply to, mentions, contacts
    static func getFastTags(_ tags:[FastTag], limit:Int = 500, subscriptionId:String? = nil) -> String? {
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
["REQ", "\(subscriptionId ?? ("AC-" + UUID().uuidString))", {"authors": ["\(pubkey)"], "kinds": [3], "limit": \(limit)}]
"""
    }
    
    static func getAuthorContactsLists(pubkeys:[String], limit:Int = 3000, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? ("ACLS-" + UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)), "kinds": [3], "limit": \(limit)}]
"""
    }
    
    static func getFollowers(pubkey:String, since:NTimestamp? = nil, subscriptionId:String? = nil) -> String {
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? ("FOLL-" + UUID().uuidString))", {"#p": ["\(pubkey)"], "kinds": [3], "since": \(since.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? ("FOLL-" + UUID().uuidString))", {"#p": ["\(pubkey)"], "kinds": [3]}]
"""
    }
    
    static func getAuthorKind1(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? ("A1-" + UUID().uuidString))", {"authors": ["\(pubkey)"], "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getAuthorNotes(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? ("AN-" + UUID().uuidString))", {"authors": ["\(pubkey)"], "kinds": [1,6,20,9802,30023,34235], "limit": \(limit)}]
"""
    }
    
    static func getAuthorNotesUntil(pubkey:String, until:NTimestamp, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? ("ANU-" + UUID().uuidString))", {"authors": ["\(pubkey)"], "kinds": [1,6,20,9802,30023,34235], "until": \(until.timestamp), "limit": \(limit)}]
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
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"#p": ["\(pubkey)"], "kinds": [4,1059], "limit": \(limit)}, {"authors": ["\(pubkey)"], "kinds": [4,1059], "limit": \(limit)}]
"""
    }
    
    static func getRelays(pubkeys: [String], subscriptionId: String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON.shared.toString(pubkeys)), "kinds": [3,10002,10050] }]
"""
    }
    
    static func getAuthorsNotes(pubkeys:[String], limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON.shared.toString(pubkeys)), "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getUserMetadata(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? ("UM-" + UUID().uuidString))", {"authors": ["\(pubkey)"], "kinds": [0], "limit": 1}]
"""
    }
    
    static func getUserMetadataAndBadges(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0,30008], "limit": 10}]
"""
    }
    
    static func getUserMetadataAndContactList(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0,3,10002,10050,10063], "limit": 25}]
"""
    }
    
    static func getUserProfileKinds(pubkey:String, subscriptionId:String? = nil, kinds:[Int]? = nil) -> String {
        let kindsJsonArr = JSON.shared.toString(kinds ?? [0,3,30008,10002,10050,10063])
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": \(kindsJsonArr), "limit": 25}]
"""
    }
    
    static func getUserMetadata(pubkeys:[String], limit:Int? = nil, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? ("UM-" + UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)), "kinds": [0], "since": \(since.timestamp)}]
    """
        }
        else if let until {
            return """
    ["REQ", "\(subscriptionId ?? ("UM-" + UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)), "kinds": [0], "until": \(until.timestamp)}]
    """
        }
        
        let limit = limit ?? (pubkeys.count + 20) // add 20 in case of multiple setMetadata's for a pubkey maybe?? not sure
        return """
["REQ", "\(subscriptionId ?? ("UM-" + UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)), "kinds": [0], "limit": \(limit)}]
"""
    }
}


struct EventMessageBuilder {
    
    static func makeRepost(original: Event, embedOriginal:Bool = false) -> NEvent {
        var repost = NEvent(content: embedOriginal ? original.toNEvent().eventJson() : "#[0]")
        
        let possibleRelayHints = resolveRelayHint(forPubkey: original.pubkey, receivedFromRelays: original.relays_)
        
        let firstRelay = possibleRelayHints.first ?? ""
        
        // first try to put just scheme+hostname as relay. because extra parameters in url can be irrelevant
        if let url = URL(string: firstRelay), let scheme = url.scheme, let host = url.host {
            let firstPart = (scheme + "://" + host)
            repost.tags.append(NostrTag(["e", original.id, firstPart, "mention"]))
        }
        else {
            repost.tags.append(NostrTag(["e", original.id, firstRelay, "mention"]))
        }
        repost.tags.append(NostrTag(["p", original.pubkey]))
        repost.kind = .repost
        return repost
    }
    
    static func makeReactionEvent(reactingToId: String, reactingToPubkey: String, reactionContent: String = "+") -> NEvent {
        var reactionEvent = NEvent(content: reactionContent)
        reactionEvent.kind = .reaction
        reactionEvent.tags = [NostrTag(["e", reactingToId]), NostrTag(["p", reactingToPubkey])]
        
        return reactionEvent
    }
    
    static func makeReactionEvent(reactingTo: NEvent) -> NEvent {
        var reactionEvent = NEvent(content: "+")
        reactionEvent.kind = .reaction
        reactionEvent.tags = [NostrTag(["e", reactingTo.id]), NostrTag(["p", reactingTo.publicKey])]
        
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
    
    static func makeReportEvent(pubkey: String, eventId: String, type: ReportType, note: String = "", includeProfile: Bool = false) -> NEvent {
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

// Short-hand usage example:

//    req(RM.getMentions(
//        pubkeys: [pubkey],
//        kinds: [1],
//        limit: 500,
//        since: 0
//    ))
import NostrEssentials

// outbox req has filter in ClientMessage?
func outboxReq(_ cm: NostrEssentials.ClientMessage, activeSubscriptionId: String? = nil, relays: Set<RelayData> = [], accountPubkey: String? = nil, relayType: NosturClientMessage.RelayType = .READ) {
    #if DEBUG
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
        return
    }
    #endif
    
    let _cm = NosturClientMessage(clientMessage: cm, relayType: relayType)
    
    let pubkey = (accountPubkey ?? AccountsState.shared.activeAccountPublicKey)
    
    if Thread.isMainThread {
        DispatchQueue.global().async {
            ConnectionPool.shared.sendMessage(
                _cm,
                subscriptionId: activeSubscriptionId,
                relays: relays,
                accountPubkey: pubkey
            )
        }
    }
    else {
        ConnectionPool.shared.sendMessage(
            _cm,
            subscriptionId: activeSubscriptionId,
            relays: relays,
            accountPubkey: pubkey
        )
    }
}


// old req, just string so cant do outbox with this
// will skip send eventually in ConnectionPool.shared.sendMessage() if activeSubscriptionId already in connection?.nreqSubscriptions
func req(_ rm: String, activeSubscriptionId: String? = nil, relays: Set<RelayData> = [], accountPubkey: String? = nil, relayType: NosturClientMessage.RelayType = .READ) {
    #if DEBUG
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
        return
    }
    #endif
    
    let pubkey = (accountPubkey ?? AccountsState.shared.activeAccountPublicKey)
    
    if Thread.isMainThread {
        DispatchQueue.global().async {
            ConnectionPool.shared.sendMessage(
                NosturClientMessage(
                    clientMessage: NostrEssentials.ClientMessage(
                        type: .REQ,
                        subscriptionId: activeSubscriptionId
                    ),
                    onlyForNWCRelay: activeSubscriptionId == "NWC",
                    onlyForNCRelay: activeSubscriptionId == "NC",
                    relayType: relayType,
                    message: rm
                ),
                subscriptionId: activeSubscriptionId,
                relays: relays,
                accountPubkey: pubkey
            )
        }
    }
    else {
        ConnectionPool.shared.sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(
                    type: .REQ,
                    subscriptionId: activeSubscriptionId
                ),
                onlyForNWCRelay: activeSubscriptionId == "NWC",
                onlyForNCRelay: activeSubscriptionId == "NC",
                relayType: relayType,
                message: rm
            ),
            subscriptionId: activeSubscriptionId,
            relays: relays,
            accountPubkey: pubkey
        )
    }
}

// Helper. isActiveSubscription for things where we need only 1 active subscription kept alive.
func nxReq(_ filter: NostrEssentials.Filters, subscriptionId: String, isActiveSubscription: Bool = false, relays: Set<RelayData> = [], accountPubkey: String? = nil, relayType: NosturClientMessage.RelayType = .READ, useOutbox: Bool = false) {
    
    let pubkey = (accountPubkey ?? AccountsState.shared.activeAccountPublicKey)
    
    let cm = NostrEssentials.ClientMessage(
        type: .REQ,
        subscriptionId: subscriptionId,
        filters: [filter]
    )
    
    if useOutbox {
        outboxReq(cm, activeSubscriptionId: isActiveSubscription ? subscriptionId : nil, relays: relays, accountPubkey: pubkey, relayType:  relayType)
    }
    else if let cmJsonString = cm.json() {
        req(cmJsonString, activeSubscriptionId: isActiveSubscription ? subscriptionId : nil, relays: relays, accountPubkey: pubkey, relayType: relayType)
    }
    else {
#if DEBUG
        L.og.debug("🔴🔴 Problem generating REQ (nxReq)")
#endif
    }
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
