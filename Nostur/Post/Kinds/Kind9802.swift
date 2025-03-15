//
//  Kind9802.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct Kind9802: View {
    private var theme: Theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    @ObservedObject private var highlightAttributes: HighlightAttributes
    @State private var lineLimit = 25
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let forceAutoload: Bool
    
    private let THREAD_LINE_OFFSET = 24.0
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.highlightAttributes = nrPost.highlightAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.theme = theme
        self.forceAutoload = forceAutoload
    }
    
    var body: some View {
        if isEmbedded {
            self.embeddedView
        }
        else {
            self.normalView
        }
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost))
    }
    
    @ViewBuilder
    private var normalView: some View {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: true, theme: theme) {
            
            VStack {
                Text(nrPost.content ?? "")
                    .lineLimit(lineLimit)
                    .onTapGesture(perform: {
                        withAnimation {
                            lineLimit = 150
                        }
                    })
                    .fontItalic()
                    .padding(20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let firstE = nrPost.firstE {
                            navigateTo(NotePath(id: firstE))
                        }
                        else if let aTag = nrPost.fastTags.first(where: { $0.0 == "a" }),
                                let naddr = try? ShareableIdentifier(aTag: aTag.1) {
                                navigateTo(Naddr1Path(naddr1: naddr.bech32string))
                        }
                    }
                    .overlay(alignment:.topLeading) {
                        Image(systemName: "quote.opening")
                            .foregroundColor(Color.secondary)
                    }
                    .overlay(alignment:.bottomTrailing) {
                        Image(systemName: "quote.closing")
                            .foregroundColor(Color.secondary)
                    }
                
                if let hlAuthorPubkey = highlightAttributes.authorPubkey {
                    HStack {
                        Spacer()
                        PFP(pubkey: hlAuthorPubkey, nrContact: highlightAttributes.contact, size: 20)
                            .onTapGesture {
                                navigateTo(ContactPath(key: hlAuthorPubkey))
                            }
                        Text(highlightAttributes.anyName ?? "Unknown")
                            .onTapGesture {
                                navigateTo(ContactPath(key: hlAuthorPubkey))
                            }
                    }
                    .padding(.trailing, 20)
                }
                HStack {
                    Spacer()
                    if let url = highlightAttributes.url {
                        Text("[\(url)](\(url))")
                            .lineLimit(1)
                            .font(.caption)
                    }
                }
                .padding(.trailing, 20)
            }
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
            )
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                navigateTo(nrPost)
            }
            
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost, theme: theme) {
            HighlightRenderer(nrPost: nrPost, theme: theme)
        }
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
