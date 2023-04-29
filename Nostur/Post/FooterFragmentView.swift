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
    
    let vPost:VPost
    @ObservedObject var event:Event
    @State var unpublishLikeId:UUID? = nil
    @State var liked:Bool
    @State var reposted:Bool
    
    init(vPost: VPost) {
        self.vPost = vPost
        self.event = vPost.event
        _liked = State(initialValue: vPost.liked)
        _reposted = State(initialValue: vPost.reposted)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack {
                    Image("ReplyIcon")
                    Text(event.repliesCount.description).opacity(event.repliesCount == 0 ? 0 : 1)
//                    RollingOnUpdateNumber(event.repliesCount).opacity(event.repliesCount == 0 ? 0 : 1)
                }
                .padding([.vertical, .trailing], 5)
                .contentShape(Rectangle())
                .onTapGesture { sendNotification(.createNewReply, event) }
                Spacer()
                
                // REPOST
                if (vPost.reposted || reposted) {
                    HStack {
                        Image("RepostedIcon")
                            .foregroundColor(.green)
                        Text(event.mentionsCount.description).opacity(event.mentionsCount == 0 ? 0 : 1)
//                        RollingOnUpdateNumber(event.mentionsCount).opacity(event.mentionsCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.green)
                    .padding(5)
                }
                else {
                    HStack {
                        Image("RepostedIcon")
                        Text(event.mentionsCount.description).opacity(event.mentionsCount == 0 ? 0 : 1)
//                        RollingOnUpdateNumber(event.mentionsCount).opacity(event.mentionsCount == 0 ? 0 : 1)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sendNotification(.createNewQuoteOrRepost, event)
                    }
                }
                Spacer()
                
                // LIKE
                if (vPost.liked || liked) {
                    HStack {
                        Image("LikeIconActive")
                            .foregroundColor(.red)
                        Text(event.likesCount.description).opacity(event.likesCount == 0 ? 0 : 1)
//                        RollingOnUpdateNumber(event.likesCount).opacity(event.likesCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.red)
                    .contentShape(Rectangle())
                    .padding(5)
                    .onTapGesture {
                        if unpublishLikeId != nil && up.cancel(unpublishLikeId!) {
                            ns.unlikePost(event)
                            unpublishLikeId = nil
                            liked = false
                        }
                    }
                }
                else {
                    HStack {
                        Image("LikeIcon")
                        Text(event.likesCount.description).opacity(event.likesCount == 0 ? 0 : 1)
//                        RollingOnUpdateNumber(event.likesCount).opacity(event.likesCount == 0 ? 0 : 1)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard ns.account?.privateKey != nil else {
                            ns.readOnlyAccountSheetShown = true
                            return
                        }
                        if let signedEvent = ns.likePost(event) {
                            unpublishLikeId = up.publish(signedEvent)
                            liked = true
//                            sendNotification(.viewNeedsUpdate)
                        }
                    }
                }
                Spacer()
                
                
                LightningButton(tally: event.zapTally, event: event)
                    .opacity(event.contact?.anyLud ?? false ? 1 : 0.3)
                    .disabled(!(event.contact?.anyLud ?? false))
                Spacer()  // TODO: FIXME


                // BOOKMARK
                if (ns.isBookmarked(event)) {
                    Image("BookmarkIconActive")
                        .foregroundColor(.orange)
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                        .padding(.leading, 10)
                        .onTapGesture {
                            ns.removeBookmark(event)
                        }
                }
                else {
                    Image("BookmarkIcon")
                        .padding(.vertical, 5)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                            ns.addBookmark(event)
                        }
                }
                
            }
            if (event.pubkey == ns.activeAccountPublicKey) {
                Text("Sent to \(event.relays.split(separator: " ").count) relays")
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
                Spacer()  // TODO: FIXME


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
            
            let event7 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            if (event7 != nil) {
                FooterFragmentView(vPost: event7!)
            }
        }
        .padding(.horizontal, 20)
        .withPreviewEnvironment()
    }
}
