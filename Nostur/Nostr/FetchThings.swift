//
//  FetchThings.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import Foundation
import NostrEssentials

func fetchProfiles(pubkeys: Set<String>, subscriptionId: String? = nil) {
    // Normally we use "Profiles" sub, and track the timestamp since last fetch
    // if we fetch someone elses feed, the sub is not "Profiles" but "SomeoneElsesProfiles", and we skip the date check
    let since = subscriptionId?.starts(with: "Profiles-") ?? false ? (Nostur.account()?.lastProfileReceivedAt ?? nil) : nil
    let sinceNTimestamp = since != nil ? NTimestamp(date: since!) : nil
    L.fetching.info("checking profiles since: \(since?.description ?? "")")
    
    ConnectionPool.shared
        .sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(
                    type: .REQ,
                    subscriptionId: subscriptionId,
                    filters: [Filters(authors: pubkeys, kinds: [0], since: sinceNTimestamp?.timestamp)]
                ),
                relayType: .READ
            ),
            subscriptionId: subscriptionId
        )
}

func fetchEvents(pubkeys: Set<String>, amount: Int? = 5000, since: Int64? = nil, subscriptionId: String? = nil) {
    ConnectionPool.shared
        .sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(
                    type: .REQ,
                    subscriptionId: subscriptionId,
                    filters: [Filters(authors: pubkeys, kinds: [1,5,6,20,9802,30023,34235], since: since != nil ? Int(since!) : nil, limit: amount)]
                ),
                relayType: .READ
            ),
            subscriptionId: subscriptionId
        )
}

func fetchStuffForLastAddedNotes(ids:[String]) {
    guard !ids.isEmpty else {
        L.og.error("🔴🔴 fetchStuffForLastAddedNotes, ids is empty, fix it.")
        return
    }
    
    let sub = "VIEWING-"+UUID().uuidString
    
    ConnectionPool.shared
        .sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(
                    type: .REQ,
                    subscriptionId: sub,
                    filters: [Filters(kinds: [1,6,7,9735], tagFilter: TagFilter(tag: "e", values: Set(ids)), limit: 5000)]
                ),
                relayType: .READ
            ),
            subscriptionId: sub
        )
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

func serializedR(_ tag:String) -> String {
    return "[\"r\",\"\(tag)"
}
