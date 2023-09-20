//
//  FooterAttributes.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI
import CoreData

class FooterAttributes: ObservableObject {
    @Published var replyPFPs:[URL] = []
    
    @Published var replied:Bool
    @Published var repliesCount:Int64
    
    @Published var reposted:Bool
    @Published var repostsCount:Int64 // was mentionsCount
    
    @Published var liked:Bool
    @Published var likesCount:Int64
    
    @Published var zapsCount:Int64
    @Published var zapTally:Int64
    
    @Published var bookmarked:Bool
    
    init(replyPFPs:[URL] = [], event:Event, repliesCount:Int64 = 0) {
        self.replyPFPs = replyPFPs
        
        self.replied = Self.isReplied(event)
        self.repliesCount = max(event.repliesCount, repliesCount)
        
        self.reposted = Self.isReposted(event)
        self.repostsCount = event.repostsCount
        
        self.liked = Self.isLiked(event)
        self.likesCount = event.likesCount
        
        self.zapsCount = event.zapsCount
        self.zapTally = event.zapTally
        
        self.bookmarked = Self.isBookmarked(event)
    }
    
    static private func isBookmarked(_ event:Event) -> Bool {
        if let account = account(), let bookmarks = account.bookmarks {
            return bookmarks.contains(event)
        }
        return false
    }
    
    static private func isLiked(_ event:Event) -> Bool {
        if let account = account() {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at >= %i AND reactionToId == %@ AND pubkey == %@ AND kind == 7", event.created_at, event.id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
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
            fr.predicate = NSPredicate(format: "created_at > %i AND repostForId == %@ AND pubkey == %@",
                                       event.created_at, event.id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
}
