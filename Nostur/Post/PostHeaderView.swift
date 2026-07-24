//
//  PostHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2024.
//

import SwiftUI

struct NRPostHeaderContainer: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.containerID) private var containerID
    /// Observed so live-chat room titles can appear after async room resolve
    @ObservedObject private var nrPost: NRPost
    @ObservedObject var settings: SettingsStore = .shared
    @ObservedObject var nrContact: NRContact
    private var singleLine: Bool = true
    private var isDetail: Bool = false

    init(nrPost: NRPost, singleLine: Bool = true, isDetail: Bool = false) {
        self.nrPost = nrPost
        self.nrContact = if let fromPubkey = nrPost.fromPubkey {
            NRContact.instance(of: fromPubkey)
        } else {
            nrPost.contact
        }
        self.singleLine = singleLine
        self.isDetail = isDetail
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(pubkey: nrPost.pubkey, name: nrContact.anyName, onTap: nameTapped, via: nrPost.via, createdAt: nrPost.createdAt, agoText: nrPost.ago, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine, restricted: nrPost.isRestricted, isPrivate: nrPost.isPrivate, nrContact: nrContact, isDetail: isDetail, isAnonPost: AnonReplySession.shared.isAnonPubkey(nrPost.pubkey), isLiveChat: nrPost.isLiveChatMessage, liveChatRoomTitle: nrPost.liveChatRoomTitle)
                .onDisappear {
                    if nrContact.metadata_created_at == 0 {
                        QueuedFetcher.shared.dequeue(pTag: nrContact.pubkey)
                    }
                }
        }
    }
    
    private func nameTapped() {
        guard !nxViewingContext.contains(.preview) else { return }
        navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, nrPost: nrPost, context: containerID)
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
    public var isPrivate: Bool = false
    public var nrContact: NRContact? = nil
    public var isDetail: Bool = false
    public var isAnonPost: Bool = false
    /// Kind 1311 live chat mention: show "· chat · Room title" after the time
    public var isLiveChat: Bool = false
    public var liveChatRoomTitle: String? = nil

    var body: some View {
//#if DEBUG
//        let _ = nxLogChanges(of: Self.self)
//#endif
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
            if isAnonPost {
                Text("you · anon")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .layoutPriority(2)
            }
            if isPrivate {
                PrivateLabel()
                    .lineLimit(1)
                    .infoText("This is a private post. Only you or the intended recipients can see it.")
            }
            else if restricted {
                RestrictedLabel()
                    .lineLimit(1)
                    .infoText("The author has marked this post as restricted.\n\nA restricted post is intended to be sent only to specific relays and should not be rebroadcasted to other relays.")
            }

            if let nrContact {
                PossibleImposterLabelView(nrContact: nrContact)
            }

            if (singleLine) {
                Ago(createdAt, agoText: agoText)
                    .equatable()
                    .layoutPriority(2)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                liveChatLabel
                
                if !isLiveChat, displayUserAgentEnabled, let via = via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
                
                if shouldShowFollowButton {
                    FollowLink(pubkey: pubkey)
                        .layoutPriority(2)
                        .lineLimit(1)
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

                liveChatLabel
                
                if !isLiveChat, displayUserAgentEnabled, let via = via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .foregroundColor(.secondary)
                }
                
                if isDetail {
                    Text(verbatim: "·")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(createdAt.formatted(date: .numeric, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .layoutPriority(3)
                }
                
                if shouldShowFollowButton {
                    FollowLink(pubkey: pubkey)
                        .layoutPriority(2)
                        .lineLimit(1)
                }
            }
        }
    }
    
    @ViewBuilder
    private var liveChatLabel: some View {
        if isLiveChat {
            Text(verbatim: "·")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("chat", comment: "Label next to time indicating a live chat mention notification")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .layoutPriority(2)
            if let liveChatRoomTitle, !liveChatRoomTitle.isEmpty {
                Text(verbatim: "·")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(liveChatRoomTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
    }
    
    // Only show Follow button in contexts where inline following is useful.
    // Don't show for imposter, post preview, or screenshot views.
    private var shouldShowFollowButton: Bool {
        if let nrContact, nrContact.similarToPubkey != nil {
            return false
        }
        guard nxViewingContext.isDisjoint(with: [.preview, .screenshot]) else { return false }

        return nxViewingContext.contains(.feedPreview)
            || (isDetail && !la.isFollowing(pubkey: pubkey))
            || la.viewFollowingPublicKeys.count < 50
    }
}


struct RestrictedLabel: View {
    @Environment(\.theme) private var theme
    
    var body: some View {
        Text("restricted", comment: "Label shown on a restricted post").font(.system(size: 12.0))
            .padding(.horizontal, 8)
            .background(theme.accent.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top, 3)
            .layoutPriority(2)
    }
}

struct PrivateLabel: View {
    @Environment(\.theme) private var theme
    
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 12.0))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(theme.accent)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top, 3)
            .layoutPriority(2)
    }
}

struct PrivateTextLabel: View {
    @Environment(\.theme) private var theme
    
    var body: some View {
        Text("private", comment: "Label shown on a private item").font(.system(size: 12.0))
            .padding(.horizontal, 8)
            .background(theme.accent.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top, 3)
            .layoutPriority(2)
    }
}
