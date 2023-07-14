//
//  FooterFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import SwiftUI

struct FooterFragmentView: View {
    
    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)

    @ObservedObject var nrPost:NRPost
    var isDetail = false
    @State var unpublishLikeId:UUID? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack {
                    Image(nrPost.replied ? "ReplyIconActive" : "ReplyIcon")
                        .foregroundColor(nrPost.replied ? Color("AccentColor") : Self.grey)
                    AnimatedNumber(number: nrPost.repliesCount)
                        .equatable()
                        .opacity(nrPost.repliesCount == 0 ? 0 : 1)
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
                        AnimatedNumber(number: nrPost.likesCount)
                            .equatable()
                            .opacity(nrPost.likesCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.red)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
                            NosturState.shared.unlikePost(nrPost.mainEvent)
                            unpublishLikeId = nil
                            nrPost.unlike()
                        }
                    }
                }
                else {
                    HStack {
                        Image("LikeIcon")
                        AnimatedNumber(number: nrPost.likesCount)
                            .equatable()
                            .opacity(nrPost.likesCount == 0 ? 0 : 1)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard NosturState.shared.account?.privateKey != nil else {
                            NosturState.shared.readOnlyAccountSheetShown = true
                            return
                        }
                        
                        guard let account = NosturState.shared.account else { return }
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                        
                //      1. create kind 7 event based on kind 1 event:
                        let likeEvent = EventMessageBuilder.makeReactionEvent(reactingTo: nrPost.mainEvent)
                //      2. sign that event with account keys
                        nrPost.mainEvent.likesCount += 1
                        
                        if account.isNC {
                            NosturState.shared.nsecBunker?.requestSignature(forEvent: likeEvent, whenSigned: { signedEvent in
                                unpublishLikeId = Unpublisher.shared.publish(signedEvent)
                            })
                        }
                        else {
                            guard let signedEvent = try? NosturState.shared.signEvent(likeEvent) else {
                                L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                                return
                            }
                            unpublishLikeId = Unpublisher.shared.publish(signedEvent)
                        }
                        nrPost.like()                        
                    }
                }
                Spacer()
                
                if !IS_APPLE_TYRANNY {
                    ZapButton(tally: nrPost.zapTally, nrPost: nrPost)
                        .opacity(nrPost.contact?.anyLud ?? false ? 1 : 0.3)
                        .disabled(!(nrPost.contact?.anyLud ?? false))
                    Spacer()
                }
                
                
                // BOOKMARK
                if (nrPost.bookmarked) {
                    Image("BookmarkIconActive")
                        .foregroundColor(.orange)
                        .padding(5)
                        .contentShape(Rectangle())
                    //                        .padding(.leading, 10)
                        .onTapGesture {
                            NosturState.shared.removeBookmark(nrPost.mainEvent)
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
                            NosturState.shared.addBookmark(nrPost.mainEvent)
                        }
                }
                
            }
            if (nrPost.pubkey == NosturState.shared.activeAccountPublicKey) {
                Text("Sent to \(nrPost.relays.split(separator: " ").count) relays", comment:"Message shown in footer of sent post")
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
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            VStack {
                
                PreviewFooterFragmentView()
                
                if let p = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                    FooterFragmentView(nrPost: p)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
