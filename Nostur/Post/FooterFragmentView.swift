//
//  FooterFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import SwiftUI

struct FooterFragmentView: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var nrPost:NRPost // TODO: Remove @ObservedObject from nrPost and scope to footerAttributes
    @ObservedObject var footerAttributes:NRPost.FooterAttributes
    var isDetail = false
    @State var unpublishLikeId:UUID? = nil
    var relaysCount:Int {
        nrPost.relays.split(separator: " ").count
    }
    
    init(nrPost: NRPost, isDetail: Bool = false) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.footerAttributes = nrPost.footerAttributes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack {
                    Image(nrPost.replied ? "ReplyIconActive" : "ReplyIcon")
                        .foregroundColor(nrPost.replied ? Color("AccentColor") : theme.footerButtons)
                    AnimatedNumber(number: nrPost.repliesCount)
                        .equatable()
                        .opacity(nrPost.repliesCount == 0 ? 0 : 1)
                    if !isDetail && !footerAttributes.replyPFPs.isEmpty {
                        ZStack(alignment:.leading) {
                            ForEach(footerAttributes.replyPFPs.indices, id:\.self) { index in
                                MiniPFP(pictureUrl: footerAttributes.replyPFPs[index])
                                    .id(index)
                                    .zIndex(-Double(index))
                                    .offset(x:Double(0 + (15*index)))
                            }
                        }
                    }
                }
                .padding([.vertical, .trailing], 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    sendNotification(.createNewReply, EventNotification(event: nrPost.event))
                }
                Spacer()
                
                // REPOST
                if (nrPost.reposted) {
                    HStack {
                        Image("RepostedIcon")
                            .foregroundColor(.green)
                        AnimatedNumber(number: nrPost.repostsCount)
                            .equatable()
                            .opacity(nrPost.repostsCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.green)
                    .padding(5)
                }
                else {
                    HStack {
                        Image("RepostedIcon")
                        AnimatedNumber(number: nrPost.repostsCount)
                            .equatable()
                            .opacity(nrPost.repostsCount == 0 ? 0 : 1)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sendNotification(.createNewQuoteOrRepost, nrPost.event.toMain())
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
                            nrPost.unlike()
                            unpublishLikeId = nil
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
                        
                        var likeNEvent = nrPost.like()
                        
                        if account.isNC {
                            likeNEvent.publicKey = account.publicKey
                            likeNEvent = likeNEvent.withId()
                            unpublishLikeId = UUID()
                            NosturState.shared.nsecBunker?.requestSignature(forEvent: likeNEvent, whenSigned: { signedEvent in
                                if let unpublishLikeId = self.unpublishLikeId {
                                    self.unpublishLikeId = Unpublisher.shared.publish(signedEvent, cancellationId: unpublishLikeId)
                                }
                            })
                        }
                        else {
                            guard let signedEvent = try? account.signEvent(likeNEvent) else {
                                L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                                return
                            }
                            unpublishLikeId = Unpublisher.shared.publish(signedEvent)
                        }
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
                        .padding([.top,.leading,.bottom], 5)
                        .overlay {
                            Color.clear
                                .frame(width: 30)
                                .offset(x: -10)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                            TapGesture()
                                                .onEnded { _ in
                                                    NosturState.shared.removeBookmark(nrPost)
                                                }
                                        )
                        }
                }
                else {
                    Image("BookmarkIcon")
                        .padding([.top,.leading,.bottom], 5)
                        .overlay {
                            Color.clear
                                .frame(width: 30)
                                .offset(x: -10)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                            TapGesture()
                                                .onEnded { _ in
                                                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                                    impactMed.impactOccurred()
                                                    NosturState.shared.addBookmark(nrPost)
                                                }
                                        )
                        }
                }
                
            }
//            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 28)
//            .readSize { size in
//                print("Footer size: \(size)")
//            }
            if (isOwnPost) {
                
                if (nrPost.relays == "" && (nrPost.cancellationId != nil || nrPost.flags == "nsecbunker_unsigned" || nrPost.flags == "awaiting_send")) {
                    HStack {
                        if nrPost.flags == "nsecbunker_unsigned" {
                            Text("Signing post...")
                        }
                        else {
                            Text("Sending post...")
                        }
                        Spacer()
                        if nrPost.flags != "nsecbunker_unsigned" {
                            Button("Send now") {
                                nrPost.sendNow()
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(theme.accent)
                            .opacity(nrPost.flags == "nsecbunker_unsigned" ? 0 : 1.0)
                            .padding(.trailing, 5)
                        }
                        Button("Undo") {
                            nrPost.unpublish()
                        }
                        .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                        .foregroundColor(Color.white)
                        .opacity(nrPost.flags == "nsecbunker_unsigned" ? 0 : 1.0)
                    }
                    .padding(.bottom, 5)
                    .foregroundColor(Color.primary)
                    .fontWeight(.bold)
                }
                else if !nrPost.isPreview && nrPost.flags != "awaiting_send" && nrPost.flags != "nsecbunker_unsigned" {
                    HStack {
                        if nrPost.flags == "nsecbunker_unsigned" && nrPost.relays != "" {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                        }
                        else if relaysCount == 0 {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                        }
                        Text("Sent to \(relaysCount) relays", comment:"Message shown in footer of sent post")
                        Spacer()
                    }
                    .padding(.bottom, 5)
                }
            }
        }
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))        
    }
    
    var isOwnPost:Bool {
        if nrPost.pubkey == NosturState.shared.activeAccountPublicKey { return true }
        guard let account = NosturState.shared.accounts.first(where: { $0.publicKey == nrPost.pubkey }) else { return false }
        return account.privateKey != nil
    }
}


struct PreviewFooterFragmentView: View {
    
    @EnvironmentObject var theme:Theme
    
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
//                    .padding(.trailing, 5)
                
            }
        }
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))
        
        
    }
}

struct FooterFragmentView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            VStack(spacing: 0) {
                
                PreviewFooterFragmentView()
                
                if let p = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                    FooterFragmentView(nrPost: p)
                }
            }
//            .padding(.horizontal, 20)
        }
    }
}
