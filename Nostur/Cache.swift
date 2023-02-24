//
//  Cache.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import Foundation

typealias EventId = String

struct SavedEventsCache {
    static var shared:LRUCache<EventId, NTimestamp> = {
        let cache = LRUCache<EventId, NTimestamp>(capacity: 2000)
        return cache
    }()
}

struct FailedURLCache {
    static var shared:LRUCache<String, Date> = {
        let cache = LRUCache<String, Date>(capacity: 2000)
        return cache
    }()
}

//// TO PREVENT SENDING DUPLICATE MESSAGES
//struct LastSentMessagesCache {
//    static var shared:LRUCache<EventId, NTimestamp> = {
//        let cache = LRUCache<EventId, NTimestamp>(capacity: 2000)
//        return cache
//    }()
//}
