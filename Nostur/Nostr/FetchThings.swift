//
//  FetchThings.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import Foundation

func fetchProfiles(pubkeys:Set<String>, subscriptionId:String? = nil) {
    let since = NosturState.shared.lastProfileReceivedAt ?? nil
    let sinceNTimestamp = since != nil ? NTimestamp(date: since!) : nil
    L.fetching.info("checking profiles since: \(since?.description ?? "")")
    
    SocketPool.shared
        .sendMessage(ClientMessage(
            type: .REQ,
            message: RequestMessage.getUserMetadata(pubkeys: Array(pubkeys),
                                                    subscriptionId: subscriptionId, since: sinceNTimestamp)), subscriptionId: subscriptionId)
}

func fetchEvents(pubkeys:Set<String>, amount:Int? = 5000, since:Int64? = nil, subscriptionId:String? = nil) {
//    print("💿💿 getFollowingEvents for \(pubkeys.count) pubkeys 💿💿")
    if (since != nil) {
        
        let req = RequestMessage.getFollowingEvents(
            pubkeys: Array(pubkeys),
            limit: amount!,
            subscriptionId: subscriptionId,
            since: NTimestamp(timestamp: Int(since!))
        )
        
        let clientMessage = ClientMessage(
            type: .REQ,
            message: req
        )
        
        SocketPool.shared.sendMessage(clientMessage, subscriptionId:subscriptionId)
    }
    else {
        let req = RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!, subscriptionId: subscriptionId)
        let clientMessage = ClientMessage(
            type: .REQ,
            message: req
        )
        SocketPool.shared.sendMessage(clientMessage, subscriptionId:subscriptionId)
    }
}

// SAME BUT pubkeys already in string
func fetchEvents(pubkeysString:String, amount:Int? = 5000, since:Int64? = nil, subscriptionId:String? = nil) {
//    print("💿💿 getFollowingEvents for \(pubkeys.count) pubkeys 💿💿")
    if (since != nil) {
        
        let req = RequestMessage.getFollowingEvents(
            pubkeysString: pubkeysString,
            limit: amount!,
            subscriptionId: subscriptionId,
            since: NTimestamp(timestamp: Int(since!))
        )
        
        let clientMessage = ClientMessage(
            type: .REQ,
            message: req
        )
        
        SocketPool.shared.sendMessage(clientMessage, subscriptionId:subscriptionId)
    }
    else {
        let req = RequestMessage.getFollowingEvents(pubkeysString: pubkeysString, limit: amount!, subscriptionId: subscriptionId)
        let clientMessage = ClientMessage(
            type: .REQ,
            message: req
        )
        SocketPool.shared.sendMessage(clientMessage, subscriptionId:subscriptionId)
    }
}

func fetchStuffForLastAddedNotes(ids:[String]) {
    req(RM.getEventReferences(ids: ids, subscriptionId: "VIEWING-"+UUID().uuidString))
}

func pubkeys(_ contacts:[Contact]) -> [String] {
    return contacts.map { $0.pubkey }
}

func ids(_ events:[Event]) -> [String] {
    return events.map { $0.id }
}

func ids(_ events:Array<Event>.SubSequence) -> [String] {
    return events.map { $0.id }
}

func ids(_ nrPosts:[NRPost]) -> [String] {
    return nrPosts.map { $0.id }
}

func pubkeys(_ events:[Event]) -> [String] {
    return events.map { $0.pubkey }
}

func toId(_ event:Event) -> String {
    return event.id
}

func toPubkey(_ event:Event) -> String {
    return event.pubkey
}

func toPubkey(_ contact:Contact) -> String {
    return contact.pubkey
}


func serializedP(_ pubkey:String) -> String {
    return "[\"p\",\"\(pubkey)"
}


func serializedE(_ id:String) -> String {
    return "[\"e\",\"\(id)"
}

func serializedT(_ tag:String) -> String {
    return "[\"t\",\"\(tag)"
}
