//
//  ViewUpdates.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2024.
//

import Foundation
import Combine

class ViewUpdates {
    
    static let shared = ViewUpdates()
    
    private init() { }
    
    public var profileUpdates = PassthroughSubject<ProfileInfo, Never>()
    public var bookmarkUpdates = PassthroughSubject<BookmarkUpdate, Never>()
    public var feedUpdates = PassthroughSubject<FeedUpdate, Never>()
    public var relatedUpdates = PassthroughSubject<RelatedUpdate, Never>()
    
    public func sendMockProfileUpdate() {
        profileUpdates.send(ProfileInfo(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", name: Int.random(in: 1...33).description, pfpUrl: Int.random(in: 44...500).description))
    }
    
    public func sendMockBookmarkUpdate() {
        bookmarkUpdates.send(BookmarkUpdate(id: "3a72941da6030f155b6e5209e96057aec77ab3851a60bce61a36227c327c5322", isBookmarked: Bool.random()))
    }
    
    public var zapStateChanged = PassthroughSubject<ZapStateChange, Never>()
    public var eventStatChanged = PassthroughSubject<EventStatChange, Never>()
    public var repliesUpdated = PassthroughSubject<EventRepliesChange, Never>()
    public var postDeleted = PassthroughSubject<(toDelete: String, deletedBy: String), Never>()
    public var eventRelationUpdate = PassthroughSubject<EventRelationUpdate, Never>()
    public var contactUpdated = PassthroughSubject<Contact, Never>()
    public var nip05updated = PassthroughSubject<(pubkey: String, isVerified: Bool, nip05: String, nameOnly: String), Never>() //
    public var updateNRPost = PassthroughSubject<Event, Never>()
    public var replacableEventUpdate = PassthroughSubject<Event, Never>()
}

struct ZapStateChange {
    let pubkey: String
    var eTag: String?
    var aTag: String?
    var zapState: ZapState?
}

struct EventRelationUpdate {
    let relationType: EventRelationType
    let id: String
    var event: Event
}

enum EventRelationType {
    case replyTo
    case replyToRoot
    case replyToRootInverse
    case firstQuote
}

struct EventRepliesChange {
    let id: String
    let replies: [Event] // replies
}

struct EventStatChange {
    let id: String
    var replies: Int64? // replies
    var reposts: Int64? // reposts
    var likes: Int64? // likes (reactions), reposts,
    var zaps: Int64? // zaps
    var zapTally: Int64? // total zap amount
    var detectedRelay: String? // update view with new detected sent-to relay (after "OK")
}

public enum ZapState: String {
    case initiated = "INITIATED"
    case nwcConfirmed = "NWC_CONFIRMED"
    case zapReceiptConfirmed = "ZAP_RECEIPT_CONFIRMED"
    case failed = "FAILED"
    case cancelled = "CANCELLED" // (by Undo)
}

struct ProfileInfo {
    let pubkey: String
    var name: String?
    var pfpUrl: String?
}

struct BookmarkUpdate {
    let id: String
    let isBookmarked: Bool
}

struct EventUpdate {
    let id: String
    let relays: String
}

struct FeedUpdate {
    let id = UUID()
    let type: FeedType
    let accountPubkey: String
}

enum FeedType {
    case Reactions
    case Reposts
    case Mentions
    case Zaps
    case Follows
}

struct RelatedUpdate {
    let id = UUID()
    let type: RelatedType
    let eventId: String
}

enum RelatedType {
    case Reactions
    case Zaps
}

struct AccountData: Identifiable, Hashable {
    var id: String { publicKey }
    
    let publicKey: String
    let lastSeenPostCreatedAt: Int64
    
    let followingPubkeys: Set<String>
    let privateFollowingPubkeys: Set<String>
    let followingHashtags: Set<String>
    
    var picture: String?
    var banner: String?
    let flags: Set<String>
    let isNC: Bool
    let anyName: String
}
