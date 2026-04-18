//
//  Cache.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import SwiftUI

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
    
    private let lock = NSLock()
    
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
        lock.lock()
        let count = initializedCaches.count
        lock.unlock()
        return count == 5
    }
    
    
    public func getBookmarkColor(_ eventId: String) -> Color? {
        lock.lock()
        let result = bookmarkedIds[eventId]
        lock.unlock()
        return result
    }
    
    @MainActor
    public func addBookmark(_ eventId: String, color: Color) {
        lock.lock()
        bookmarkedIds[eventId] = color
        lock.unlock()
    }
    
    @MainActor
    public func removeBookmark(_ eventId: String) {
        lock.lock()
        bookmarkedIds[eventId] = nil
        lock.unlock()
    }
    
    public func getOurReactions(_ eventId: String) -> Set<String> {
        lock.lock()
        let result = reactions[eventId] ?? []
        lock.unlock()
        return result
    }
        
    public func hasReaction(_ eventId: String, reactionType: String) -> Bool {
        lock.lock()
        let result = reactionIds[reactionType]?.contains(eventId) ?? false
        lock.unlock()
        return result
    }
    
    @MainActor
    public func addReaction(_ eventId: String, reactionType: String) {
        lock.lock()
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
        lock.unlock()
    }
    
    @MainActor
    public func removeReaction(_ eventId: String, reactionType: String) {
        lock.lock()
        reactionIds[reactionType]?.remove(eventId)
        reactions[eventId] = nil
        lock.unlock()
    }
    
    public func isRepliedTo(_ eventId: String) -> Bool {
        lock.lock()
        let result = repliedToIds.contains(eventId)
        lock.unlock()
        return result
    }
    
    @MainActor
    public func addRepliedTo(_ eventId: String) {
        lock.lock()
        repliedToIds.insert(eventId)
        lock.unlock()
    }
    
    @MainActor
    public func removeRepliedTo(_ eventId: String) {
        lock.lock()
        repliedToIds.remove(eventId)
        lock.unlock()
    }
    
    public func isReposted(_ eventId: String) -> Bool {
        lock.lock()
        let result = repostedIds.contains(eventId)
        lock.unlock()
        return result
    }
    
    @MainActor
    public func addReposted(_ eventId: String) {
        lock.lock()
        repostedIds.insert(eventId)
        lock.unlock()
    }
    
    @MainActor
    public func removeReposted(_ eventId: String) {
        lock.lock()
        repostedIds.remove(eventId)
        lock.unlock()
    }
    
    public func isZapped(_ eventId: String) -> Bool {
        lock.lock()
        let result = zappedIds.contains(eventId)
        lock.unlock()
        return result
    }
    
    @MainActor
    public func addZapped(_ eventId: String) {
        lock.lock()
        zappedIds.insert(eventId)
        lock.unlock()
    }
    
    @MainActor
    public func removeZapped(_ eventId: String) {
        lock.lock()
        zappedIds.remove(eventId)
        lock.unlock()
    }
    
    
    
    
    
    
    private func initBookmarked() {
        let bookmarks: [(eventId: String, color: Color)] = Bookmark.fetchAll(context: bg()).compactMap {
            guard let eventId = $0.eventId else { return nil }
            return (eventId: eventId, color: $0.color)
        }
        Task { @MainActor in
            self.lock.lock()
            for bookmark in bookmarks {
                self.bookmarkedIds[bookmark.eventId] = bookmark.color
            }
            self.initializedCaches.insert("bookmarks")
            self.lock.unlock()
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
            self.lock.lock()
            self.reactions = reactions
            self.reactionIds = reactionIds
            self.initializedCaches.insert("reactions")
            self.lock.unlock()
        }
    }
    
    private func initReplied(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN {1,1111,1244}", pubkey)
        let allRepliedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.replyToId })
        Task { @MainActor in
            self.lock.lock()
            self.repliedToIds = allRepliedIds
            self.initializedCaches.insert("replies")
            self.lock.unlock()
        }
    }
    
    private func initReposted(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 6 AND pubkey == %@", pubkey)
        let allRepostedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.firstQuoteId })
    
        Task { @MainActor in
            self.lock.lock()
            self.repostedIds = allRepostedIds
            self.initializedCaches.insert("reposts")
            self.lock.unlock()
        }
    }
    
    private func initZapped(_ pubkey: String) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 9734 AND pubkey == %@", pubkey)
        let allZappedIds = Set(((try? bg().fetch(fr)) ?? []).compactMap { $0.firstE() })

        Task { @MainActor in
            self.lock.lock()
            self.zappedIds = allZappedIds
            self.initializedCaches.insert("zaps")
            self.lock.unlock()
        }
    }
    
}
