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
    @Published var replyPFPs:[URL] = []
    
    @Published var replied:Bool
    @Published var repliesCount:Int64
    
    @Published var reposted:Bool
    @Published var repostsCount:Int64 // was mentionsCount
    
    @Published var liked:Bool
    @Published var likesCount:Int64
    @Published var reactions:Set<String> = []
    
    @Published var zapped = false
    @Published var zapsCount:Int64
    @Published var zapTally:Int64
    
    @Published var bookmarked:Bool
    @Published var hasPrivateNote:Bool
    
    private var zapState:Event.ZapState?
    private var withFooter:Bool
    private var event:Event
    private var subscriptions = Set<AnyCancellable>()
    private var id:String
    
    init(replyPFPs:[URL] = [], event:Event, withFooter:Bool = true, repliesCount:Int64 = 0) {
        self.event = event
        self.id = event.id
        self.withFooter = withFooter
        self.replyPFPs = replyPFPs
        
        self.replied = withFooter && Self.isReplied(event)
        self.repliesCount = max(event.repliesCount, repliesCount)
        
        self.reposted = withFooter && Self.isReposted(event)
        self.repostsCount = event.repostsCount
        
        self.liked = withFooter && Self.isLiked(event)
        self.likesCount = event.likesCount
        self.reactions = withFooter ? Self.loadReactions(event) : []
        
        self.zapState = withFooter && Self.hasZapReceipt(event) ? .zapReceiptConfirmed : event.zapState
        self.zapped = [.initiated, .nwcConfirmed, .zapReceiptConfirmed].contains(zapState)
        self.zapsCount = event.zapsCount
        self.zapTally = event.zapTally
        
        self.bookmarked = withFooter && Self.isBookmarked(event)
        self.hasPrivateNote = withFooter && Self.hasPrivateNote(event)
        
        
        if withFooter {
            self.setupListeners()
        }
    }
    
    @MainActor public func loadFooter() {
        bg().perform {
            guard !self.withFooter else { return }
            self.withFooter = true
            self.setupListeners()
            
            let isReplied = Self.isReplied(self.event)
            let isReposted = Self.isReposted(self.event)
            let isLikes = Self.isLiked(self.event)
            let reactions = Self.loadReactions(self.event)
            let isBookmarked = Self.isBookmarked(self.event)
            let hasPrivateNote = Self.hasPrivateNote(self.event)
//            let zapsCount = self.event.zapsCount
//            let zapTally = self.event.zapTally
            
            self.zapState = Self.hasZapReceipt(self.event) ? .zapReceiptConfirmed : self.event.zapState
            let isZapped = [.initiated, .nwcConfirmed, .zapReceiptConfirmed].contains(self.zapState)
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.replied = isReplied
                self.reposted = isReposted
                self.liked = isLikes
                self.reactions = reactions
                self.bookmarked = isBookmarked
                self.hasPrivateNote = hasPrivateNote
                self.zapped = isZapped
//                self.zapsCount = zapsCount
//                self.zapTally = zapTally
            }
        }
        
    }
    
    @MainActor public func cancelZap(_ cancellationId:UUID) {
        _ = Unpublisher.shared.cancel(cancellationId)
        NWCRequestQueue.shared.removeRequest(byCancellationId: cancellationId)
        NWCZapQueue.shared.removeZap(byCancellationId: cancellationId)
        zapped = false
        bg().perform {
            self.zapState = .cancelled
        }
    }
    
    private func setupListeners() {
        repostsListener()
        likesListener()
        zapsListener()
        actionListener()
    }
    
    private func repostsListener() {
        event.repostsDidChange
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] reposts in // Int64
                guard let self = self else { return }
//                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.repostsCount = reposts
//                }
            }
            .store(in: &subscriptions)
    }
    
    private func likesListener() {
        event.likesDidChange
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] likes in
                guard let self = self else { return }
//                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.likesCount = likes
//                }
                
                // Also update own like (or slow? disbaled)
//                if !self.liked && isLiked() { // nope. main bg thread mismatch
//                    self.liked = true
//                }
            }
            .store(in: &subscriptions)
    }
    
    private func zapsListener() {
        event.zapsDidChange
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] (count, tally) in
                guard let self = self else { return }
//                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.zapTally = tally
                    self.zapsCount = count
//                }
            }
            .store(in: &subscriptions)
        
        event.zapStateChanged
            .sink { [weak self] zapState in
                guard let self = self else { return }
                guard let zapState = zapState else { return }
                
                let isZapped = [.initiated, .nwcConfirmed, .zapReceiptConfirmed].contains(zapState)
                
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.zapped = isZapped
                }
            }
            .store(in: &subscriptions)
    }
    
    private func actionListener() {
        receiveNotification(.postAction)
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
                let action = notification.object as! PostActionNotification
                guard action.eventId == self.id else { return }
                
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    switch action.type {
                    case .bookmark:
                        self.bookmarked = action.bookmarked
                    case .liked:
                        self.liked = true
                    case .replied:
                        self.replied = true
                    case .reposted:
                        self.reposted = true
                    case .privateNote:
                        self.hasPrivateNote = action.hasPrivateNote
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    static private func isBookmarked(_ event:Event) -> Bool {
        // TODO: Need to cache this, update cache when bookmarks change
        let allBookmarks = Set(Bookmark.fetchAll(context: bg()).compactMap({ $0.eventId }))
        
        return allBookmarks.contains(event.id)
    }
    
    static private func isLiked(_ event:Event) -> Bool {
        if let account = account() {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at >= %i AND reactionToId == %@ AND pubkey == %@ AND kind == 7 AND content == \"+\"", event.created_at, event.id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    static private func loadReactions(_ event:Event) -> Set<String> {
        if let account = account() {
            let fr = NSFetchRequest<NSDictionary>(entityName: "Event")
            fr.sortDescriptors = []
            fr.predicate = NSPredicate(format: "created_at >= %i AND reactionToId == %@ AND pubkey == %@ AND kind == 7", event.created_at, event.id, account.publicKey)
            fr.fetchLimit = 20
            fr.resultType = .dictionaryResultType
            fr.propertiesToFetch = ["content"]
            guard let reactions = try? DataProvider.shared().bg.fetch(fr) else {
                return []
            }
            return Set(reactions.compactMap { $0["content"] as? String })
        }
        return []
    }
    
    static private func isReplied(_ event:Event) -> Bool {
        if let account = account() {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at > %i AND replyToId == %@ AND pubkey == %@ AND kind == 1", event.created_at, event.id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    static private func isReposted(_ event:Event) -> Bool {
        if let account = account() {
            let fr = Event.fetchRequest()
            // TODO: Should use a generic .otherId, similar to .otherPubkey, to make all relational queries superfast.
            fr.predicate = NSPredicate(format: "created_at > %i AND kind == 6 AND pubkey == %@ AND tagsSerialized CONTAINS %@",
                                       event.created_at, account.publicKey, serializedE(event.id))
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    static private func hasZapReceipt(_ event:Event) -> Bool {
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
        if let account = account(), let notes = account.privateNotes {
            return notes.first(where: { $0.post == event }) != nil
        }
        return false
    }
}
