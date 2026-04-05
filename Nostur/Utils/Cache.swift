//
//  Cache.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import SwiftUI
import os.lock

typealias EventId = String

struct PubkeyUsernameCache {
    static let shared: LRUCache2<String, String> = {
        let cache = LRUCache2<String, String>(countLimit: 2500)
        return cache
    }()
}

func nameOrPubkey(_ pubkey: String) -> String {
    return PubkeyUsernameCache.shared.retrieveObject(at: pubkey) ?? pubkey
}

struct NRContactCache {
    static let shared: LRUCache2<String, NRContact> = {
        let cache = LRUCache2<String, NRContact>(countLimit: 3000)
        return cache
    }()
}

struct EventCache {
    static let shared: LRUCache2<String, Event> = {
        let cache = LRUCache2<String, Event>(countLimit: IS_CATALYST ? 8000 : 2000)
        return cache
    }()
}


class LinkPreviewCache {
    
    public let cache = LRUCache2<URL, [String: String]>(countLimit: 500)
    
    public let metaTagsRegex = try! NSRegularExpression(pattern: #"<meta\s+(?:property=|name=)"(?:og|twitter):(.*?)"\s+content="([^"]+)(?:"\s|"[^>]*?\/?>)"#, options: .caseInsensitive)
    
    public let titleRegex = try! NSRegularExpression(pattern: "<title(?:.*)>([^<]*)</title>", options: .caseInsensitive)
    
    static let shared = LinkPreviewCache()
    
    private init() {}
}

class AccountCache {
    
    // For every post render we need to hit the database to see if we have bookmarked, reacted, replied or zapped. Better cache that here.
    // Reads happen from bg threads (NRPost.init), writes always happen on @MainActor.
    // Lock protects against concurrent read-during-write races on the CoW value types.
    
    private var _lock = os_unfair_lock()
    
    public let pubkey: String
    private var bookmarkedIds: [String: Color] = [:]
    private var repostedIds: Set<String> = []
    private var repliedToIds: Set<String> = []
    private var zappedIds: Set<String> = []
    private var reactionIds: [String: Set<String>] = [:] // emoji -> reaction ids
    private var reactions: [String: Set<String>] = [:] // id -> reaction emoji
    private var initializedCaches: Set<String> = []
    
    init(_ pubkey: String) {
        self.pubkey = pubkey
        initBookmarked()
        initReactions(pubkey)
        initReplied(pubkey)
        initReposted(pubkey)
        initZapped(pubkey)
    }
    
    public var cacheIsReady: Bool {
        os_unfair_lock_lock(&_lock)
        let count = initializedCaches.count
        os_unfair_lock_unlock(&_lock)
        return count == 5
    }
    
    
    public func getBookmarkColor(_ eventId: String) -> Color? {
        os_unfair_lock_lock(&_lock)
        let result = bookmarkedIds[eventId]
        os_unfair_lock_unlock(&_lock)
        return result
    }
    
    @MainActor
    public func addBookmark(_ eventId: String, color: Color) {
        os_unfair_lock_lock(&_lock)
        bookmarkedIds[eventId] = color
        os_unfair_lock_unlock(&_lock)
    }
    
    @MainActor
    public func removeBookmark(_ eventId: String) {
        os_unfair_lock_lock(&_lock)
        bookmarkedIds[eventId] = nil
        os_unfair_lock_unlock(&_lock)
    }
    
    public func getOurReactions(_ eventId: String) -> Set<String> {
        os_unfair_lock_lock(&_lock)
        let result = reactions[eventId] ?? []
        os_unfair_lock_unlock(&_lock)
        return result
    }
        
    public func hasReaction(_ eventId: String, reactionType: String) -> Bool {
        os_unfair_lock_lock(&_lock)
        let result = reactionIds[reactionType]?.contains(eventId) ?? false
        os_unfair_lock_unlock(&_lock)
        return result
    }
    
    @MainActor
    public func addReaction(_ eventId: String, reactionType: String) {
        os_unfair_lock_lock(&_lock)
        if reactionIds[reactionType] == nil {
            reactionIds[reactionType] = [eventId]
        } else {
            reactionIds[reactionType]?.insert(eventId)
        }
        if reactions[eventId] == nil {
            reactions[eventId] = [reactionType]
        } else {
            reactions[eventId]?.insert(reactionType)
        }
        os_unfair_lock_unlock(&_lock)
    }
    
    @MainActor
    public func removeReaction(_ eventId: String, reactionType: String) {
        os_unfair_lock_lock(&_lock)
        reactionIds[reactionType]?.remove(eventId)
        reactions[eventId] = nil
        os_unfair_lock_unlock(&_lock)
    }
    
    public func isRepliedTo(_ eventId: String) -> Bool {
        os_unfair_lock_lock(&_lock)
        let result = repliedToIds.contains(eventId)
        os_unfair_lock_unlock(&_lock)
        return result
    }
    
    @MainActor
    public func addRepliedTo(_ eventId: String) {
        os_unfair_lock_lock(&_lock)
        repliedToIds.insert(eventId)
        os_unfair_lock_unlock(&_lock)
    }
    
    @MainActor
    public func removeRepliedTo(_ eventId: String) {
        os_unfair_lock_lock(&_lock)
        repliedToIds.remove(eventId)
        os_unfair_lock_unlock(&_lock)
    }
    
    public func isReposted(_ eventId: String) -> Bool {
        os_unfair_lock_lock(&_lock)
        let result = repostedIds.contains(eventId)
        os_unfair_lock_unlock(&_lock)
        return result
    }
    
    @MainActor
    public func addReposted(_ eventId: String) {
        os_unfair_lock_lock(&_lock)
        repostedIds.insert(eventId)
        os_unfair_lock_unlock(&_lock)
    }
    
    @MainActor
    public func removeReposted(_ eventId: String) {
        os_unfair_lock_lock(&_lock)
        repostedIds.remove(eventId)
        os_unfair_lock_unlock(&_lock)
    }
    
    public func isZapped(_ eventId: String) -> Bool {
        os_unfair_lock_lock(&_lock)
        let result = zappedIds.contains(eventId)
        os_unfair_lock_unlock(&_lock)
        return result
    }
    
    @MainActor
    public func addZapped(_ eventId: String) {
        os_unfair_lock_lock(&_lock)
        zappedIds.insert(eventId)
        os_unfair_lock_unlock(&_lock)
    }
    
    @MainActor
    public func removeZapped(_ eventId: String) {
        os_unfair_lock_lock(&_lock)
        zappedIds.remove(eventId)
        os_unfair_lock_unlock(&_lock)
    }
    
    
    
    
    
    
    private func initBookmarked() {
        let bookmarks: [(eventId: String, color: Color)] = Bookmark.fetchAll(context: bg()).compactMap {
            guard let eventId = $0.eventId else { return nil }
            return (eventId: eventId, color: $0.color)
        }
        Task { @MainActor in
            os_unfair_lock_lock(&self._lock)
            for bookmark in bookmarks {
                self.bookmarkedIds[bookmark.eventId] = bookmark.color
            }
            self.initializedCaches.insert("bookmarks")
            os_unfair_lock_unlock(&self._lock)
        }
    }
    
    private func initReactions(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind == 7", pubkey)
        let allReactions = (try? bg().fetch(fr)) ?? []
        
        var reactionIds: [String: Set<String>] = [:] // enoji -> reaction ids
        var reactions: [String: Set<String>] = [:] // reaction id -> emojis
        
        for reaction in allReactions {
            guard let reactionToId = reaction.reactionToId else {
                continue
            }
            
            if reactions[reactionToId] == nil {
                reactions[reactionToId] = [reaction.content ?? "+"]
            }
            else {
                reactions[reactionToId]?.insert(reaction.content ?? "+")
            }
            
            let reactionType = reaction.content ?? "+"
            if reactionIds[reactionType] == nil {
                reactionIds[reactionType] = [reactionToId]
            }
            else {
                reactionIds[reactionType]?.insert(reactionToId)
            }
        }

        Task { @MainActor in
            os_unfair_lock_lock(&self._lock)
            self.reactions = reactions
            self.reactionIds = reactionIds
            self.initializedCaches.insert("reactions")
            os_unfair_lock_unlock(&self._lock)
        }
    }
    
    private func initReplied(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN {1,1111,1244}", pubkey)
        let allRepliedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.replyToId })
        Task { @MainActor in
            os_unfair_lock_lock(&self._lock)
            self.repliedToIds = allRepliedIds
            self.initializedCaches.insert("replies")
            os_unfair_lock_unlock(&self._lock)
        }
    }
    
    private func initReposted(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 6 AND pubkey == %@", pubkey)
        let allRepostedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.firstQuoteId })
    
        Task { @MainActor in
            os_unfair_lock_lock(&self._lock)
            self.repostedIds = allRepostedIds
            self.initializedCaches.insert("reposts")
            os_unfair_lock_unlock(&self._lock)
        }
    }
    
    private func initZapped(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 9734 AND pubkey == %@", pubkey)
        let allZappedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.firstE() })

        Task { @MainActor in
            os_unfair_lock_lock(&self._lock)
            self.zappedIds = allZappedIds
            self.initializedCaches.insert("zaps")
            os_unfair_lock_unlock(&self._lock)
        }
    }
    
}
