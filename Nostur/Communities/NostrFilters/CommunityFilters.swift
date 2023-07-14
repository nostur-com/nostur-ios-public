//
//  CommunityFilters.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/07/2023.
//
//

import Foundation


//{
//  "authors": ["<Author pubkey>", "<Moderator1 pubkey>", "<Moderator2 pubkey>", "<Moderator3 pubkey>", ...],
//  "kinds": [4550],
//  "#a": ["34550:<Community event author pubkey>:<d-identifier of the community>"],
//}

extension RequestMessage {
    
    static func getCommunities(pubkeys:[String]? = nil, subscriptionId:String? = nil, since:NTimestamp = NTimestamp(timestamp: 0)) -> String {
        if let pubkeys {
            return """
["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)),  "kinds": [34550], "since": \(since.timestamp) }]
"""
        }
        
        return """
["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", { "kinds": [34550], "since": \(since.timestamp) }]
"""
    }
    
    static func getCommunityApprovedPosts(communityAuthorPubkey pubkey:String, communityId:String, moderatorPubkeys pubkeys:[String], kinds:[Int] = [4550], limit:Int = 500, subscriptionId:String? = nil, since:NTimestamp? = nil, until:NTimestamp? = nil) -> String {
        if let since {
            return """
    ["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)), "since": \(since.timestamp), "kinds": \(JSON.shared.toString(kinds)), "#a": ["34550:\(pubkey):\(communityId)"], "limit": \(limit) }]
    """
        }
        else if let until {
            return """
    ["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)), "until": \(until.timestamp), "kinds": \(JSON.shared.toString(kinds)), "#a": ["34550:\(pubkey):\(communityId)"], "limit": \(limit) }]
    """
        }
        return """
    ["REQ", "\(subscriptionId ?? ("M-"+UUID().uuidString))", {"authors": \(JSON.shared.toString(pubkeys)), "#a": ["34550:\(pubkey):\(communityId)"], "limit": \(limit), "kinds": \(JSON.shared.toString(kinds)) }]
    """
    }
}


