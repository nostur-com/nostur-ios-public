//
//  Cache.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import Foundation

typealias EventId = String

struct FailedURLCache {
    static let shared:LRUCache2<String, Date> = {
        let cache = LRUCache2<String, Date>(countLimit: 2000)
        return cache
    }()
}

struct PubkeyUsernameCache {
    static let shared:LRUCache2<String, String> = {
        let cache = LRUCache2<String, String>(countLimit: 5000)
        return cache
    }()
}

struct LinkPreviewCache {
    static let shared:LRUCache2<URL, [String: String]> = {
        let cache = LRUCache2<URL, [String: String]>(countLimit: 2000)
        return cache
    }()
}
