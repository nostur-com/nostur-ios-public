//
//  Event+communities.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/07/2023.
//
//

import Foundation
import CoreData


// NIP-172
// https://github.com/vitorpamplona/nips/blob/moderated-communities/172.md

extension Event {
    
    var communityName:String {
        fastTags.first(where: { $0.0 == "d" })?.1 ?? ""
    }
    
    var communityDescription:String {
        fastTags.first(where: { $0.0 == "description" })?.1 ?? ""
    }
    
    var communityImage:String? {
        fastTags.first(where: { $0.0 == "image" })?.1
    }
    
    var communityModerators:[ModeratorPTag] {
        fastTags.filter { $0.0 == "p" && $0.3 == "moderator" }
    }
    
    var communityRelays:[CommunityRelay] {
        fastTags.filter { $0.0 == "relay" }
            .map { ($0.0, $0.1, $0.2) }
    }
}

typealias ModeratorPTag = (String, String, String?, String?)
typealias CommunityRelay = (String, String, String?)


extension Event {
    
    static func fetchCommunities(context:NSManagedObjectContext) -> [Event] {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 34550 AND mostRecentId == nil")
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        return (try? context.fetch(fr)) ?? []
    }
}

//{
//  "id": "<32-bytes lowercase hex-encoded SHA-256 of the the serialized event data>",
//  "pubkey": "<32-bytes lowercase hex-encoded public key of the event creator>",
//  "created_at": "<Unix timestamp in seconds>",
//  "kind": 34550,
//  "tags": [
//    ["d", "<Community name>"],
//    ["description", "<Community description>"],
//    ["image", "<Community image url>", "<Width>x<Height>"],
//
//    //.. other tags relevant to defining the community
//
//    // moderators
//    ["p", "<32-bytes hex of a pubkey1>", "<optional recommended relay URL>", "moderator"],
//    ["p", "<32-bytes hex of a pubkey2>", "<optional recommended relay URL>", "moderator"],
//    ["p", "<32-bytes hex of a pubkey3>", "<optional recommended relay URL>", "moderator"],
//
//    // relays used by the community (w/optional marker)
//    ["relay", "<relay hosting author kind 0>", "author"],
//    ["relay", "<relay where to send and receive requests>", "requests"],
//    ["relay", "<relay where to send and receive approvals>", "approvals"],
//    ["relay", "<relay where to post requests to and fetch approvals from>"]
//  ]
//}
