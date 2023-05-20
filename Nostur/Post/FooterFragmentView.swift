//
//  FooterFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import SwiftUI

struct FooterFragmentView: View {
    
    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)
    
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    
    @ObservedObject var nrPost:NRPost
    @State var unpublishLikeId:UUID? = nil

    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack {
                    Image(nrPost.replied ? "ReplyIconActive" : "ReplyIcon")
                        .foregroundColor(nrPost.replied ? Color("AccentColor") : Self.grey)
                    AnimatedNumber(number: nrPost.repliesCount).opacity(nrPost.repliesCount == 0 ? 0 : 1)
                }
                .padding([.vertical, .trailing], 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let replyTo = nrPost.event.toMain() {
                        sendNotification(.createNewReply, replyTo)
                    }
                }
                Spacer()
                
                // REPOST
                if (nrPost.reposted) {
                    HStack {
                        Image("RepostedIcon")
                            .foregroundColor(.green)
                        Text("0").opacity(0)
//                        AnimatedNumber(number: nrPost.mentionsCount).opacity(nrPost.mentionsCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.green)
                    .padding(5)
                }
                else {
                    HStack {
                        Image("RepostedIcon")
                        Text("0").opacity(0)
//                        AnimatedNumber(number: nrPost.mentionsCount).opacity(nrPost.mentionsCount == 0 ? 0 : 1)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let mainEvent = nrPost.event.toMain() {
                            sendNotification(.createNewQuoteOrRepost, mainEvent)
                        }
                    }
                }
                Spacer()
                
                // LIKE
                if (nrPost.liked) {
                    HStack {
                        Image("LikeIconActive")
                            .foregroundColor(.red)
                        AnimatedNumber(number: nrPost.likesCount).opacity(nrPost.likesCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.red)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if unpublishLikeId != nil && up.cancel(unpublishLikeId!) {
                            ns.unlikePost(nrPost.mainEvent)
                            unpublishLikeId = nil
                            nrPost.unlike()
                        }
                    }
                }
                else {
                    HStack {
                        Image("LikeIcon")
                        AnimatedNumber(number: nrPost.likesCount).opacity(nrPost.likesCount == 0 ? 0 : 1)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard ns.account?.privateKey != nil else {
                            ns.readOnlyAccountSheetShown = true
                            return
                        }
                        if let signedEvent = ns.likePost(nrPost.mainEvent) {
                            unpublishLikeId = up.publish(signedEvent)
                            nrPost.like()
                        }
                    }
                }
                Spacer()
                                
                LightningButton(tally: nrPost.zapTally, nrPost: nrPost)
                    .opacity(nrPost.contact?.anyLud ?? false ? 1 : 0.3)
                    .disabled(!(nrPost.contact?.anyLud ?? false))
                Spacer()


                // BOOKMARK
                if (nrPost.bookmarked) {
                    Image("BookmarkIconActive")
                        .foregroundColor(.orange)
                        .padding(5)
                        .contentShape(Rectangle())
//                        .padding(.leading, 10)
                        .onTapGesture {
                            ns.removeBookmark(nrPost.mainEvent)
                        }
                }
                else {
                    Image("BookmarkIcon")
                        .padding(5)
//                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                            ns.addBookmark(nrPost.mainEvent)
                        }
                }
                
            }
            if (nrPost.pubkey == ns.activeAccountPublicKey) {
                Text("Sent to \(nrPost.relays.split(separator: " ").count) relays")
                    .padding(.bottom, 5)
            }
        }
        .foregroundColor(Self.grey)
            .font(.system(size: 14))
            
            
    }
}


struct PreviewFooterFragmentView: View {
    
    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack {
                    Image("ReplyIcon")
                    Text("0").opacity(0)
                }
                .padding([.vertical, .trailing], 5)
                Spacer()
                
                // REPOST
                HStack {
                    Image("RepostedIcon")
                    Text("0").opacity(0)
                }
                .padding(5)
                Spacer()
                
                // LIKE
                HStack {
                    Image("LikeIcon")
                    Text("0").opacity(0)
                }
                .padding(5)
                Spacer()
                
                
                Image("BoltIcon")
                Text("0").opacity(0)
                Spacer()


                Image("BookmarkIcon")
                    .padding(.vertical, 5)
                    .padding(.leading, 10)
                
            }
        }
        .foregroundColor(Self.grey)
            .font(.system(size: 14))
            
            
    }
}

struct FooterFragmentView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            
            PreviewFooterFragmentView()
            
            let event7 = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            if (event7 != nil) {
                FooterFragmentView(nrPost: event7!)
            }
        }
        .padding(.horizontal, 20)
        .withPreviewEnvironment()
    }
}
