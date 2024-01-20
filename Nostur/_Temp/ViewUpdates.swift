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
    
    public func sendMockProfileUpdate() {
        profileUpdates.send(ProfileInfo(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", name: Int.random(in: 1...33).description, pfpUrl: Int.random(in: 44...500).description))
    }
    
    public func sendMockBookmarkUpdate() {
        bookmarkUpdates.send(BookmarkUpdate(id: "3a72941da6030f155b6e5209e96057aec77ab3851a60bce61a36227c327c5322", isBookmarked: Bool.random()))
    }
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
