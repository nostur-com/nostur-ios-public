//
//  FooterAttributes.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI
import CoreData
import Combine

class FooterAttributes: ObservableObject {
    
    @Published var replyPFPs: [URL] = []
    
    @Published var replied: Bool
    @Published var repliesCount: Int64
    
    @Published var reposted: Bool
    @Published var repostsCount: Int64 // was mentionsCount
    
    @Published var liked: Bool
    @Published var likesCount: Int64
    
    @Published var zapsCount: Int64
    @Published var zapTally: Int64
    
    @Published var bookmarked: Bool
    @Published var hasPrivateNote: Bool
    
    public var zapState: ZapState?
    private var withFooter: Bool
    private var event: Event
    private var pubkey: String // need for zap info
    private var id: String
    
    init(replyPFPs: [URL] = [], event: Event, withFooter: Bool = true, repliesCount: Int64 = 0) {
        self.event = event
        self.pubkey = event.pubkey
        self.id = event.id
        self.withFooter = withFooter
        self.replyPFPs = replyPFPs
        
        self.replied = withFooter && Self.isReplied(event)
        self.repliesCount = max(event.repliesCount, repliesCount)
        
        self.reposted = withFooter && Self.isReposted(event)
        self.repostsCount = event.repostsCount
        
        self.liked = withFooter && Self.isLiked(event)
        self.likesCount = event.likesCount
        
        self.zapState = withFooter && Self.hasZapReceipt(event) ? .zapReceiptConfirmed : event.zapState
        
        self.zapsCount = event.zapsCount
        self.zapTally = event.zapTally
        
        self.bookmarked = withFooter && Self.isBookmarked(event)
        self.hasPrivateNote = withFooter && Self.hasPrivateNote(event)
        
        
        if withFooter {
            self.setupListeners()
        }
    }
    
    @MainActor public func loadFooter() {
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.withFooter else { return }
            self.withFooter = true
            self.setupListeners()
            
            let isReplied = Self.isReplied(self.event)
            let isReposted = Self.isReposted(self.event)
            let isLikes = Self.isLiked(self.event)
            let isBookmarked = Self.isBookmarked(self.event)
            let hasPrivateNote = Self.hasPrivateNote(self.event)
//            let zapsCount = self.event.zapsCount
//            let zapTally = self.event.zapTally
            
            self.zapState = Self.hasZapReceipt(self.event) ? .zapReceiptConfirmed : self.event.zapState
//            let isZapped = [.initiated, .nwcConfirmed, .zapReceiptConfirmed].contains(self.zapState)
            
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
                self?.replied = isReplied
                self?.reposted = isReposted
                self?.liked = isLikes
                self?.bookmarked = isBookmarked
                self?.hasPrivateNote = hasPrivateNote
//                self?.zapped = isZapped
//                self.zapsCount = zapsCount
//                self.zapTally = zapTally
            }
        }
        
    }
    
    @MainActor public func cancelZap(_ cancellationId: UUID) {
        _ = Unpublisher.shared.cancel(cancellationId)
        NWCRequestQueue.shared.removeRequest(byCancellationId: cancellationId)
        NWCZapQueue.shared.removeZap(byCancellationId: cancellationId)
        self.zapState = .cancelled
        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: pubkey, eTag: id, zapState: .cancelled))
    }
    
    private var eventStatChangeSubscription: AnyCancellable?
    private var postActionSubscription: AnyCancellable?
    
    private func setupListeners() {
        guard eventStatChangeSubscription == nil else { return }
        let id = self.id
        eventStatChangeSubscription = ViewUpdates.shared.eventStatChanged
            .filter { $0.id == id }
//            .debounce(for: .seconds(1), scheduler: DispatchQueue.main) // Adjust the debounce time as needed
//                .scan(nil) { (accumulated: EventStatChange?, change: EventStatChange) -> EventStatChange? in
//                    if let acc = accumulated, acc.id == change.id {
//                        var mergedChange = acc
//                        mergedChange.replies = change.replies ?? acc.replies
//                        mergedChange.replies = change.replies ?? acc.replies
//                        mergedChange.likes = change.likes ?? acc.likes
//                        mergedChange.zaps = change.zaps ?? acc.zaps
//                        mergedChange.zapTally = change.zapTally ?? acc.zapTally
//                        return mergedChange
//                    }
//                    return change
//                }
//                .compactMap { $0 } // Filter out nil values
//                .sink { combinedChange in
//                    // Handle the single combined change here
//                }
//                .store(in: &subscriptions) // Assuming you have a subscriptions array
//            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                
                self.objectWillChange.send()
                if let likes = change.likes, likes != self.likesCount {
                    self.likesCount = likes
                }
                if let replies = change.replies, replies != self.repliesCount {
                    self.repliesCount = replies
                }
                if let reposts = change.reposts, reposts != self.repostsCount {
                    self.repostsCount = reposts
                }
                if let zaps = change.zaps, zaps != self.zapsCount {
                    self.zapsCount = zaps
                }
                if let zapTally = change.zapTally, zapTally != self.zapTally {
                    self.zapTally = zapTally
                }
//                if let relaysCount = change.relaysCount {
//                    self.relays = relaysCount
//                }
                
                // Also update own like (or slow? disabled)
//                if !self.liked && isLiked() { // nope. main bg thread mismatch
//                    self.liked = true
//                }
            }
        
        actionListener()
    }

    
    private func actionListener() {
        guard postActionSubscription == nil else { return }
        postActionSubscription = receiveNotification(.postAction)
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
                let action = notification.object as! PostActionNotification
                guard action.eventId == self.id else { return }
                
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                    switch action.type {
                    case .bookmark:
                        self?.bookmarked = action.bookmarked
                    case .liked(let uuid):
                        self?.liked = true
                    case .unliked:
                        self?.liked = false
                    case .replied:
                        self?.replied = true
                    case .reposted:
                        self?.reposted = true
                    case .privateNote:
                        self?.hasPrivateNote = action.hasPrivateNote
                    }
                }
            }
    }
    
    static private func isBookmarked(_ event:Event) -> Bool {
        if let accountCache = accountCache() {
            return accountCache.isBookmarked(event.id)
        }
        
        // TODO: Need to cache this, update cache when bookmarks change
        let allBookmarks = Set(Bookmark.fetchAll(context: bg()).compactMap({ $0.eventId }))
        
        return allBookmarks.contains(event.id)
    }
    
    static private func isLiked(_ event:Event) -> Bool {
        if let accountCache = accountCache() {
            return accountCache.isLiked(event.id)
        }
        if let account = account() {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at >= %i AND reactionToId == %@ AND pubkey == %@ AND kind == 7 AND content == \"+\"", event.created_at, event.id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? bg().count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    static private func isReplied(_ event:Event) -> Bool {
        if let accountCache = accountCache() {
            return accountCache.isRepliedTo(event.id)
        }
        if let account = account() {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at > %i AND replyToId == %@ AND pubkey == %@ AND kind == 1", event.created_at, event.id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? bg().count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    static private func isReposted(_ event:Event) -> Bool {
        if let accountCache = accountCache() {
            return accountCache.isReposted(event.id)
        }
        if let account = account() {
            let fr = Event.fetchRequest()
            // TODO: Should use a generic .otherId, similar to .otherPubkey, to make all relational queries superfast.
            fr.predicate = NSPredicate(format: "created_at > %i AND kind == 6 AND pubkey == %@ AND tagsSerialized CONTAINS %@",
                                       event.created_at, account.publicKey, serializedE(event.id))
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? bg().count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    static private func hasZapReceipt(_ event:Event) -> Bool {
        if let accountCache = accountCache() {
            return accountCache.isZapped(event.id)
        }
        if let account = account() {
            let fr = Event.fetchRequest()
            // TODO: Should use a generic .otherId, similar to .otherPubkey, to make all relational queries superfast.
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind == 9734 AND pubkey == %@ AND tagsSerialized CONTAINS %@", event.created_at, account.publicKey, serializedE(event.id))
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? bg().count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    static private func hasPrivateNote(_ event:Event) -> Bool {
        return event.privateNote != nil
    }
}
