//
//  PostEmbeddedView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

struct PostEmbeddedLayout<Content: View>: View {
    
    @ObservedObject private var nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    @ObservedObject private var postRowDeletableAttributes: PostRowDeletableAttributes
    private var forceAutoload: Bool
    private var fullWidth: Bool
    private var theme: Theme
    @EnvironmentObject private var parentDIM: DIMENSIONS
    @State private var couldBeImposter: Int16

    private let content: Content
    private let authorAtBottom: Bool
    
    init(nrPost: NRPost, fullWidth: Bool = false, forceAutoload: Bool = false, theme: Theme, authorAtBottom: Bool = false, @ViewBuilder _ content: () -> Content) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.forceAutoload = forceAutoload
        self.fullWidth = fullWidth
        self.theme = theme
        self.couldBeImposter = nrPost.pfpAttributes.contact?.couldBeImposter ?? -1
        self.authorAtBottom = authorAtBottom
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) { // name + reply + context menu
                VStack(alignment: .leading) { // Name + menu "replying to"
                    if !authorAtBottom {
                        HStack(spacing: 5) {
                            // profile image
                            PFP(pubkey: nrPost.pubkey, pictureUrl: pfpAttributes.pfpURL, size: 20, forceFlat: nrPost.isScreenshot)
                                .onTapGesture(perform: navigateToContact)
                            
                            Text(pfpAttributes.anyName) // Name
                                .animation(.easeIn, value: pfpAttributes.anyName)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .fontWeightBold()
                                .lineLimit(1)
                                .onTapGesture(perform: navigateToContact)
                                
                            if couldBeImposter == 1 {
                                PossibleImposterLabel(possibleImposterPubkey: nrPost.pubkey, followingPubkey: nrPost.contact?.similarToPubkey)
                            }
                            
                            Group {
                                Text(verbatim: " ·") //
                                Ago(nrPost.createdAt)
                                    .equatable()
                                if let via = nrPost.via {
                                    Text(" · via \(via)") //
                                        .lineLimit(1)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        }
                    }
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                }
                
                Spacer()
            }
            VStack(alignment: .leading) {
                content
            }
            if authorAtBottom {
                HStack(spacing: 5) {
                    Spacer()
                    // profile image
                    PFP(pubkey: nrPost.pubkey, pictureUrl: pfpAttributes.pfpURL, size: 20, forceFlat: nrPost.isScreenshot)
                        .onTapGesture(perform: navigateToContact)
                    
                    Text(pfpAttributes.anyName) // Name
                        .animation(.easeIn, value: pfpAttributes.anyName)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .fontWeightBold()
                        .lineLimit(1)
                        .onTapGesture(perform: navigateToContact)
                        
                    if couldBeImposter == 1 {
                        PossibleImposterLabel(possibleImposterPubkey: nrPost.pubkey, followingPubkey: nrPost.contact?.similarToPubkey)
                    }
                    
                    Group {
                        Text(verbatim: " ·") //
                        Ago(nrPost.createdAt)
                            .equatable()
                        if let via = nrPost.via {
                            Text(" · via \(via)") //
                                .lineLimit(1)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .background(
            theme.background
                .cornerRadius(8)
                .onTapGesture(perform: navigateToPost)
        )
        .task {
            guard let nrContact = nrPost.contact else { return }
            guard !SettingsStore.shared.lowDataMode else { return }
            guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
            guard nrContact.metadata_created_at != 0 else { return }
            guard nrContact.couldBeImposter == -1 else { return }
            
            guard let la = AccountsState.shared.loggedInAccount else { return }
            guard la.account.publicKey != nrContact.pubkey else { return }
            guard !la.isFollowing(pubkey: nrContact.pubkey) else { return }
            
            guard !NewOnboardingTracker.shared.isOnboarding else { return }
            guard let followingCache = AccountsState.shared.loggedInAccount?.followingCache else { return }

            let contactAnyName = nrContact.anyName.lowercased()
            let currentAccountPubkey = AccountsState.shared.activeAccountPublicKey
            let cPubkey = nrContact.pubkey

            bg().perform { [weak nrContact] in
                guard let nrContact else { return }
                guard let account = account() else { return }
                guard account.publicKey == currentAccountPubkey else { return }
                guard let (_, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                    pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
                }) else { return }
                
                guard let cPic = nrContact.pictureUrl, similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
                Task.detached(priority: .background) {
                    let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                    DispatchQueue.main.async { [weak nrContact] in
                        guard let nrContact else { return }
                        guard currentAccountPubkey == AccountsState.shared.activeAccountPublicKey else { return }
                        couldBeImposter = similarPFP ? 1 : 0
                        nrContact.couldBeImposter = couldBeImposter
                        bg().perform {
                            guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
                            nrContact.contact?.couldBeImposter = similarPFP ? 1 : 0
//                            DataProvider.shared().bgSave()
                        }
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.lineColor, lineWidth: 1)
        )
    }
    
    private func navigateToContact() {
        if let nrContact = nrPost.contact {
            navigateTo(nrContact)
        }
        else {
            navigateTo(ContactPath(key: nrPost.pubkey))
        }
    }
    private func navigateToPost() {
        navigateTo(nrPost)
    }
}
