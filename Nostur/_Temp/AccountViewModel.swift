//
//  AccountViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/01/2024.
//

import SwiftUI
import CoreData
import Combine

// WIP - Not used anywhere yet
class AccountViewModel: ObservableObject, Identifiable {
    
    public var id: String { publicKey }
    public let publicKey: String
    
    @Published var anyName: String
    @Published var followingPubkeys: Set<String>
    @Published var privateFollowingPubkeys: Set<String>
    @Published var followingHashtags: Set<String>
    @Published var picture: String?
    @Published var banner: String?
    
    let flags: Set<String>
    let isNC: Bool

    public var pictureUrl: URL? { // TODO: Measure, is this done when passed around views or only once at init? We want once, in bg at init. Keep views fast.
        guard let picture else { return nil }
        return URL(string: picture)
    }
    
    init(publicKey: String, followingPubkeys: Set<String>, privateFollowingPubkeys: Set<String>, followingHashtags: Set<String>, picture: String? = nil, banner: String? = nil, flags: Set<String>, isNC: Bool, anyName: String) {
        self.publicKey = publicKey
        self.followingPubkeys = followingPubkeys
        self.privateFollowingPubkeys = privateFollowingPubkeys
        self.followingHashtags = followingHashtags
        self.picture = picture
        self.banner = banner
        self.flags = flags
        self.isNC = isNC
        self.anyName = anyName
    }
    
    func isRelevantUpdate(_ update: AccountData) -> Bool {
        return update.publicKey == self.publicKey
    }
    
    func applyUpdate(_ update: AccountData) {
        self.followingPubkeys = update.followingPubkeys
        self.privateFollowingPubkeys = update.privateFollowingPubkeys
        self.followingHashtags = update.followingHashtags
        self.picture = update.picture
        self.banner = update.banner
        self.anyName = update.anyName
        self.followingHashtags = update.followingHashtags
    }
    
    var isFullAccount: Bool {
        return self.flags.contains("full_account")
    }
}
