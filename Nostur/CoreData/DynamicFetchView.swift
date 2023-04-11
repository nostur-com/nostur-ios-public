//
//  DynamicFetchView.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI
import CoreData

struct DynamicFetchView<T: NSManagedObject, Content: View>: View {
    let fetchRequest: FetchRequest<T>
    let content: (FetchedResults<T>) -> Content

    var body: some View {
        self.content(fetchRequest.wrappedValue)
    }

    init(predicate: NSPredicate?, fetchLimit:Int = 5, sortDescriptors: [NSSortDescriptor], @ViewBuilder content: @escaping (FetchedResults<T>) -> Content) {
        guard let entityName = T.entity().name else { fatalError("Unknown entity") }

        let request = NSFetchRequest<T>(entityName: entityName)
        request.fetchLimit = fetchLimit
        request.sortDescriptors = sortDescriptors
        request.predicate = predicate

        self.init(fetchRequest: request, content: content)
    }

    init(fetchRequest: NSFetchRequest<T>, @ViewBuilder content: @escaping (FetchedResults<T>) -> Content) {
        self.fetchRequest = FetchRequest<T>(fetchRequest: fetchRequest)
        self.content = content
    }
}

// TEMP ALWAYS FUNCTIONS

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
    //TODO: Fixen
    // Prepare #e filter
    // Get all events that reference our event.id's on screen
    // To update likes etc.
    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: ids)))
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

func ids(_ vPosts:[VPost]) -> [String] {
    return vPosts.map { $0.id }
}

func pubkeys(_ events:[Event]) -> [String] {
    return events.map { $0.pubkey }
}

func id(_ event:Event) -> String {
    return event.id
}

func pubkey(_ event:Event) -> String {
    return event.pubkey
}

func pubkey(_ contact:Contact) -> String {
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
