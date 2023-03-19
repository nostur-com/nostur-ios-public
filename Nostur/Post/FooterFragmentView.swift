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
//    @State var unpublishRepostId:UUID? = nil
//    @State var unpublishOriginalId:UUID? = nil
    
    @State var showingNewReply = false
    @State var showingQuoteOrRepost = false
    @State var showingNewQuoteRepost = false
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "message")
                RollingOnUpdateNumber(event.repliesCount).opacity(event.repliesCount == 0 ? 0 : 1)
            }
            .padding(5)
            .contentShape(Rectangle())
            .onTapGesture {
                showingNewReply = true
            }
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
                    showingQuoteOrRepost = true
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
//            if (event.bookmarkedBy_.contains(ns.account!)) {
            if (ns.isBookmarked(event)) { // TODO: FIXME
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.orange)
                    .contentShape(Rectangle())
                    .padding(5)
                    .padding(.leading, 10)
                    .onTapGesture {
                        ns.removeBookmark(event)
                    }
            }
            else {
                Image(systemName: "bookmark")
                    .padding(5)
                    .padding(.leading, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                        ns.addBookmark(event)
                    }
            }
            
        }
            .foregroundColor(.gray)
            .padding(.trailing, 5)
            .padding(.leading, 5)
            .font(.system(size: 14))
            .sheet(isPresented: $showingNewReply) {
                NewReply(replyTo: event)
                    .environmentObject(ns)
                    .environmentObject(up)
            }
            .sheet(isPresented: $showingNewQuoteRepost) {
                NewQuoteRepost(quotingEvent: event)
                    .environmentObject(ns)
                    .environmentObject(up)
            }
            .sheet(isPresented: $showingQuoteOrRepost) {
                QuoteOrRepostChoiceSheet(event:event, showingNewQuoteRepost:$showingNewQuoteRepost)
                    .environmentObject(ns)
                    .environmentObject(up)
                    .presentationDetents([.height(200)])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: showingNewQuoteRepost) { newValue in
                if (newValue == true) {
                    showingQuoteOrRepost = false
                }
            }
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
