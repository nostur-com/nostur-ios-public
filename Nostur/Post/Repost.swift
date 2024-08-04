//
//  Repost.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/09/2023.
//

import SwiftUI

struct Repost: View {
    private let nrPost: NRPost
    @ObservedObject private var noteRowAttributes: NoteRowAttributes
    private var hideFooter = true // For rendering in NewReply
    private var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    private var connect: ThreadConnectDirection? = nil
    private let fullWidth: Bool
    private let isReply: Bool // is reply on PostDetail (needs 2*10 less box width)
    private let isDetail: Bool
    private let grouped: Bool
    private var theme: Theme
    
    init(nrPost: NRPost, hideFooter: Bool = false, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, fullWidth: Bool = false, isReply: Bool = false, isDetail: Bool = false, grouped: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.noteRowAttributes = nrPost.noteRowAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
        self.theme = theme
    }
    
    private var shouldForceAutoLoad: Bool { // To override auto download of the reposted post
        SettingsStore.shouldAutodownload(nrPost)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            RepostHeader(repostedHeader: nrPost.repostedHeader, pubkey: nrPost.pubkey)
            if let firstQuote = noteRowAttributes.firstQuote {
                // CASE - WE HAVE REPOSTED POST ALREADY
                if firstQuote.blocked {
                    HStack {
                        Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                        Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) {
                            nrPost.unblockFirstQuote()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.leading, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .hCentered()
                }
                else {
                    KindResolver(nrPost: firstQuote, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: true, isReply: isReply, isDetail: isDetail, connect: connect, grouped: grouped, forceAutoload: shouldForceAutoLoad, theme: theme)
                        .onAppear {
                            if !nrPost.missingPs.isEmpty {
                                bg().perform {
                                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "KindResolver.001")
                                    QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                                }
                            }
                        }
                        .onDisappear {
                            if !nrPost.missingPs.isEmpty {
                                QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
                            }
                        }
                    // Extra padding reposted long form, because normal repost/post has 10, but longform uses 20
                    // so add the extra 10 here
                        .padding(.horizontal, firstQuote.kind == 30023 ? 10 : 0)
                }
            }
            else {
                theme.background
            }
        }
//        .transaction { t in t.animation = nil }
//        .frame(maxWidth: .infinity, minHeight: 150)
        .overlay {
            if let firstQuoteId = nrPost.firstQuoteId, noteRowAttributes.firstQuote == nil {
                CenteredProgressView()
                    .onAppear {
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteRow.001")
                        }
                        QueuedFetcher.shared.enqueue(id: firstQuoteId)
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(id: firstQuoteId)
                    }
            }
        }
    }
}

//struct Repost_Previews: PreviewProvider {
//    static var previews: some View {
//        Repost()
//    }
//}

struct RepostHeader: View {
    let repostedHeader:String
    let pubkey:String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.2.squarepath")
                .fontWeightBold()
                .scaleEffect(0.6)
            Text(repostedHeader)
                .font(.subheadline)
                .fontWeight(.bold)
                .onTapGesture {
                    navigateTo(ContactPath(key: pubkey))
                }
        }
        .foregroundColor(.gray)
//                .transaction { t in
//                    t.animation = nil
//                }
        .onTapGesture {
            navigateTo(ContactPath(key: pubkey))
        }
        .padding(.leading, 30)
//        .debugDimensions("RepostedHeader")
//        .frame(idealHeight: 20.0)
        .transaction { t in t.animation = nil }
//                .fixedSize(horizontal: false, vertical: true)
    }
}
