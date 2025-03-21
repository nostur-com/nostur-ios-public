//
//  FollowButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/01/2025.
//

import SwiftUI

struct FollowButton: View {
    
    public let pubkey: String
    
    // To lock FollowButton to this account (instead of current active account) (TODO)
//    public var forAccountPubkey: String? = nil
//    @State private var forAccount: CloudAccount? = nil
    
    @ObservedObject private var fg: FollowingGuardian = .shared
    
    @State private var followState: FollowState = .unfollowed
    @State private var disabled: Bool = false
    
    
    var body: some View {
        Button {
            guard isFullAccount() else { showReadOnlyMessage(); return }
            guard let la = AccountsState.shared.loggedInAccount else { return }
            
            if la.isFollowing(pubkey: pubkey) {
                if !isPrivateFollowing(pubkey) {
                    followState = .privateFollowing
                    la.follow(pubkey, privateFollow: true)
                }
                else {
                    followState = .unfollowed
                    la.unfollow(pubkey)
                }
            }
            else {
                followState = .following
                la.follow(pubkey, privateFollow: false)
            }
        } label: {
            FollowButtonInner(isFollowing: followState == .following || followState == .privateFollowing, isPrivateFollowing: followState == .privateFollowing)
        }
        .disabled(!fg.didReceiveContactListThisSession)
        
        .onAppear {
            guard let la = AccountsState.shared.loggedInAccount else { return }
            followState = getFollowState(la.account, pubkey: pubkey)
        }
        
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! CloudAccount
            followState = getFollowState(account, pubkey: pubkey)
        }
        
        // TODO: Should also pass and check account on .followsChanged
        .onReceive(receiveNotification(.followsChanged)) { notification in
            guard notification.object is Set<String> else { return }
            
            guard let la = AccountsState.shared.loggedInAccount else { return }
            followState = getFollowState(la.account, pubkey: pubkey)
        }
    }
    
    private func getFollowState(_ account: CloudAccount, pubkey: String) -> FollowState {
        if account.privateFollowingPubkeys.contains(pubkey) {
            return .privateFollowing
        }
        else if (account.followingPubkeys.contains(pubkey)) {
            return .following
        }
        else {
            return .unfollowed
        }
    }
}

enum FollowState {
    case following
    case privateFollowing
    case unfollowed
}
