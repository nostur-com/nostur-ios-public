//
//  PostHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2024.
//

import SwiftUI

struct NRPostHeaderContainer: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    private let nrPost: NRPost
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject var settings: SettingsStore = .shared
    @ObservedObject var pfpAttributes: PFPAttributes
    private var singleLine: Bool = true

    init(nrPost: NRPost, singleLine: Bool = true) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.singleLine = singleLine
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(pubkey: nrPost.pubkey, name: pfpAttributes.anyName, onTap: nameTapped, via: nrPost.via, createdAt: nrPost.createdAt, agoText: nrPost.ago, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine, restricted: nrPost.isRestricted, pfp: nrPost.pfpAttributes)
                .onDisappear {
                    guard let nrContact = nrPost.contact else {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                        return
                    }
                    if nrContact.metadata_created_at == 0 {
                        QueuedFetcher.shared.dequeue(pTag: nrContact.pubkey)
                    }
                }
        }
    }
    
    private func nameTapped() {
        guard !nxViewingContext.contains(.preview) else { return }
        guard let contact = nrPost.contact else { return }
        navigateTo(contact, context: dim.id)
    }
}

#Preview {
    PreviewContainer({ pe in
               pe.loadContacts()
               pe.loadPosts()
           }) {
               VStack {
//                   PreviewHeaderView(authorName: "Fabian", accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e")
                   if let p = PreviewFetcher.fetchNRPost("953dbf6a952f43f70dbb4d6432593ba5b7f149a786d1750e4aa4cef40522c0a0") {
                       NRPostHeaderContainer(nrPost: p)
                   }
               }
           }
}

struct PostHeaderView: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @EnvironmentObject private var la: LoggedInAccount
    
    public let pubkey: String
    public let name: String
    public var onTap: (() -> Void)? = nil
    public var via: String? = nil
    public let createdAt: Date
    public var agoText: String? = nil
    public let displayUserAgentEnabled: Bool
    public let singleLine: Bool
    public var restricted: Bool = false
    
    public var pfp: PFPAttributes? = nil

    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        HStack(alignment: .center, spacing: 5) {
            Text(name)
                .foregroundColor(.primary)
                .fontWeightBold()
                .contentTransitionOpacity()
                .lineLimit(1)
                .layoutPriority(2)
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    onTap?()
                }
            
            if restricted {
                RestrictedLabel()
                    .infoText("The author has marked this post as restricted.\n\nA restricted post is intended to be sent only to specific relays and should not be rebroadcasted to other relays.")
            }

            if let pfp {
                PossibleImposterLabelView(pfp: pfp)
            }

            if (singleLine) {
                Ago(createdAt, agoText: agoText)
                    .equatable()
                    .layoutPriority(2)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if displayUserAgentEnabled, let via = via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
                
                if let pfp, pfp.similarToPubkey == nil {
                    if !nxViewingContext.contains(.preview) && la.viewFollowingPublicKeys.count < 50 {
                        FollowLink(pubkey: pubkey)
                            .layoutPriority(2)
                            .lineLimit(1)
                    }
                }
            }
        }
        if (!singleLine) {
            HStack {
                Ago(createdAt, agoText: agoText)
                    .equatable()
                    .layoutPriority(2)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if displayUserAgentEnabled, let via = via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
                
                
                if let pfp, pfp.similarToPubkey == nil {
                    if !nxViewingContext.contains(.preview) && la.viewFollowingPublicKeys.count < 50 {
                        FollowLink(pubkey: pubkey)
                            .layoutPriority(2)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}


struct RestrictedLabel: View {
    @EnvironmentObject private var themes: Themes
    
    var body: some View {
        Text("restricted", comment: "Label shown on a restricted post").font(.system(size: 12.0))
            .padding(.horizontal, 8)
            .background(themes.theme.accent.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top, 3)
            .layoutPriority(2)
    }
}
