//
//  ViewUpdates.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2024.
//

import SwiftUI
import Combine

class ViewUpdates {
    
    static let shared = ViewUpdates()
    
    private init() { }
    
    public var profileUpdates = PassthroughSubject<ProfileInfo, Never>()
    public var bookmarkUpdates = PassthroughSubject<BookmarkUpdate, Never>()
    public var feedUpdates = PassthroughSubject<FeedUpdate, Never>()
    
    // For reloading PostReactions or PostZaps
    public var relatedUpdates = PassthroughSubject<RelatedUpdate, Never>()
//    
//    public func sendMockProfileUpdate() {
//        profileUpdates.send(ProfileInfo(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", name: Int.random(in: 1...33).description, pfp: Int.random(in: 44...500).description))
//    }
    
    public func sendMockBookmarkUpdate() {
        bookmarkUpdates.send(BookmarkUpdate(id: "3a72941da6030f155b6e5209e96057aec77ab3851a60bce61a36227c327c5322", isBookmarked: Bool.random()))
    }
    
    public var zapStateChanged = PassthroughSubject<ZapStateChange, Never>()
    public var eventStatChanged = PassthroughSubject<EventStatChange, Never>()
    public var repliesUpdated = PassthroughSubject<EventRepliesChange, Never>()
    public var postDeleted = PassthroughSubject<(toDeleteId: String, deletedById: String), Never>()
    public var eventRelationUpdate = PassthroughSubject<EventRelationUpdate, Never>()
//    public var contactUpdated = PassthroughSubject<(String, Contact), Never>()
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
    var anyName: String?
    var fixedName: String?
    
    var pfp: String?
    var pfpUrl: URL? {
        if let pfp {
            return URL(string: pfp)
        }
        return nil
    }
    
    var fixedPfp: String?
    var fixedPfpUrl: URL? {
        if let fixedPfp {
            return URL(string: fixedPfp)
        }
        return nil
    }
    
    var about: String?
    var banner: String?
    var nip05: String?
    var nip05verified: Bool
    
    var metadata_created_at: Int64
    var couldBeImposter: Int16
    var similarToPubkey: String?
    
    var lud06: String?
    var lud16: String?
    var anyLud: Bool
    var zapperPubkeys: Set<String>
}

func profileInfo(_ contact: Contact) -> ProfileInfo {
    return ProfileInfo(pubkey: contact.pubkey,
                       anyName: contact.anyName,
                       fixedName: contact.fixedName,
                       pfp: contact.picture,
                       fixedPfp: contact.fixedPfp,
                       about: contact.about,
                       banner: contact.banner,
                       nip05: contact.nip05,
                       nip05verified: contact.nip05veried,
                       metadata_created_at: contact.metadata_created_at,
                       couldBeImposter: contact.couldBeImposter,
                       similarToPubkey: contact.similarToPubkey,
                       lud06: contact.lud06,
                       lud16: contact.lud16,
                       anyLud: contact.anyLud,
                       zapperPubkeys: contact.zapperPubkeys
    )
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
    case Reposts
    case Mentions
    case Zaps
}

struct AccountData: Identifiable, Hashable {
    var id: String { publicKey }
    
    let publicKey: String
    let lastSeenPostCreatedAt: Int64
    let lastSeenRepostCreatedAt: Int64
    let lastSeenReactionCreatedAt: Int64
    let lastSeenZapCreatedAt: Int64
    
    let followingPubkeys: Set<String>
    let privateFollowingPubkeys: Set<String>
    let followingHashtags: Set<String>
    
    var picture: String?
    var banner: String?
    let flags: Set<String>
    let isNC: Bool
    let anyName: String

    var npub: String { try! NIP19(prefix: "npub", hexString: publicKey).displayString }
}
