//
//  FooterFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import SwiftUI

struct FooterFragmentView: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
    
    @ObservedObject var event:Event
    @State var unpublishLikeId:UUID? = nil
    

    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack {
                    Image(systemName: "message")
                    RollingOnUpdateNumber(event.repliesCount).opacity(event.repliesCount == 0 ? 0 : 1)
                }
                .padding([.vertical, .trailing], 5)
                .contentShape(Rectangle())
                .onTapGesture { sendNotification(.createNewReply, event) }
                Spacer()
                
                // REPOST
                if (event.reposted) {
                    HStack {
                        Image(systemName: "arrow.2.squarepath")
                        RollingOnUpdateNumber(event.mentionsCount).opacity(event.mentionsCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.green)
                    .padding(5)
                }
                else {
                    HStack {
                        Image(systemName: "arrow.2.squarepath")
                        RollingOnUpdateNumber(event.mentionsCount).opacity(event.mentionsCount == 0 ? 0 : 1)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sendNotification(.createNewQuoteOrRepost, event)
                    }
                }
                Spacer()
                
                // LIKE
                if (event.liked) {
                    HStack {
                        Image(systemName: "heart.fill")
                        RollingOnUpdateNumber(event.likesCount).opacity(event.likesCount == 0 ? 0 : 1)
                    }
                    .foregroundColor(.red)
                    .contentShape(Rectangle())
                    .padding(5)
                    .onTapGesture {
                        if unpublishLikeId != nil && up.cancel(unpublishLikeId!) {
                            ns.unlikePost(event)
                        }
                    }
                }
                else {
                    HStack {
                        Image(systemName: "heart")
                        RollingOnUpdateNumber(event.likesCount).opacity(event.likesCount == 0 ? 0 : 1)
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
                            sendNotification(.viewNeedsUpdate)
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
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(.orange)
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                        .padding(.leading, 10)
                        .onTapGesture {
                            ns.removeBookmark(event)
                        }
                }
                else {
                    Image(systemName: "bookmark")
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
        .foregroundColor(Color.init(red: 113/255, green: 118/255, blue: 123/255))
            .font(.system(size: 14))
            
            
    }
}


struct FooterFragmentView_Previews: PreviewProvider {
    static var previews: some View {
        
        let event7 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        if (event7 != nil) {
            FooterFragmentView(event: event7!)
                .withPreviewEnvironment()
        }
    }
}
