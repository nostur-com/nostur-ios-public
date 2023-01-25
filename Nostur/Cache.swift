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
