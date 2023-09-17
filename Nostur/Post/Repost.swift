//
//  Repost.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/09/2023.
//

import SwiftUI

struct Repost: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    @ObservedObject var noteRowAttributes:NRPost.NoteRowAttributes
    var hideFooter = true // For rendering in NewReply
    var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    let fullWidth:Bool
    let isReply:Bool // is reply on PostDetail (needs 2*10 less box width)
    let isDetail:Bool
    let grouped:Bool
    
    init(nrPost:NRPost, hideFooter:Bool = false, missingReplyTo:Bool = false, connect: ThreadConnectDirection? = nil, fullWidth:Bool = false, isReply:Bool = false, isDetail:Bool = false, grouped:Bool = false) {
        self.nrPost = nrPost
        self.noteRowAttributes = nrPost.noteRowAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
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
                    KindResolver(nrPost: firstQuote, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: true, isReply: isReply, isDetail:isDetail, connect: connect, grouped: grouped)
                        .onAppear {
                            if !nrPost.missingPs.isEmpty {
                                DataProvider.shared().bg.perform {
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
                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteRow.001")
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
                .fontWeight(.bold)
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
        .frame(idealHeight: 20.0)
        .transaction { t in t.animation = nil }
//                .fixedSize(horizontal: false, vertical: true)
    }
}
