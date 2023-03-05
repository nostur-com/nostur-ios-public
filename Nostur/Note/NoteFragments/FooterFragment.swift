//
//  FooterFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct FooterFragment: View {
    //    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var event:Event
    @EnvironmentObject var up:Unpublisher
    
    @State var unpublishLikeId:UUID? = nil
    
    @State var unpublishRepostId:UUID? = nil
    @State var unpublishOriginalId:UUID? = nil
    
    @State var showingNewReply = false
    
    var body: some View {
        HStack {
            
            HStack {
                Image(systemName: "message")
                Text("\(event.repliesCount)").opacity(event.repliesCount == 0 ? 0 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showingNewReply = true
            }
            Spacer()
            
            // REPOST
            if (event.reposted) {
                HStack {
                    Image(systemName: "arrow.2.squarepath")
                    Text("\(event.mentionsCount)").opacity(event.mentionsCount == 0 ? 0 : 1)
                }.foregroundColor(.green)
                .contentShape(Rectangle())
                .onTapGesture {
                    if unpublishRepostId != nil && up.cancel(unpublishRepostId!) {
                        event.reposted = false
                        event.mentionsCount -= 1
                    }
                    if unpublishOriginalId != nil && up.cancel(unpublishOriginalId!) {
//                        event.reposted = false
//                        event.mentionsCount -= 1
                    }
                }
            }
            else {
                HStack {
                    Image(systemName: "arrow.2.squarepath")
                    Text("\(event.mentionsCount)").opacity(event.mentionsCount == 0 ? 0 : 1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                    if (ns.account != nil) {
                        print("🔄🔄🔄🔄🔄🔄🔄🔄")
                        event.reposted = true
                        event.mentionsCount += 1
                        ns.account?.addToReposts(event)
                        
                        // 1. create kind 7 event based on kind 1 event:    Event
                        let repostEvent = EventMessageBuilder.makeRepost(original: event)
                        
                        // 2. sign that event with account keys             Account
                        guard let signedEvent = try? ns.signEvent(repostEvent) else {
                            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                            return
                        }
                        
                        unpublishRepostId = up.publish(signedEvent)
                        unpublishOriginalId = up.publish(event.toNEvent())
                    }
                }
            }
            Spacer()
            
            // LIKE
            if (event.liked) {
                HStack {
                    Image(systemName: "heart.fill")
                    Text("\(event.likesCount)").opacity(event.likesCount == 0 ? 0 : 1)
                }.foregroundColor(.red)
                .contentShape(Rectangle())
                .onTapGesture {
                    if unpublishLikeId != nil && up.cancel(unpublishLikeId!) {
                        event.liked = false
                        event.likesCount -= 1
                    }
                }
            }
            else {
                HStack {
                    Image(systemName: "heart")
                    Text("\(event.likesCount)").opacity(event.likesCount == 0 ? 0 : 1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                    if (ns.account != nil) {
                        print("💖💖💖💖💖💖💖💖💖💖💖💖💖💖")
                        event.liked = true
                        event.likesCount += 1
                        ns.account?.addToLikes(event)
                        
                        // 1. create kind 7 event based on kind 1 event:    Event
                        let likeEvent = EventMessageBuilder.makeReactionEvent(reactingTo: event)
                        
                        // 2. sign that event with account keys             Account
                        guard let signedEvent = try? ns.signEvent(likeEvent) else {
                            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                            return
                        }
                        
                        unpublishLikeId = up.publish(signedEvent)
                        
                       
                    }
                }
            }
            Spacer()
            
            
            LightningButton(tally: event.zapTally, event:event)
                .opacity(event.contact?.anyLud ?? false ? 1 : 0.3)
                .disabled(!(event.contact?.anyLud ?? false))
            Spacer()

            
            // BOOKMARK
            if (ns.isBookmarked(event)) {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.orange)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ns.removeBookmark(event)
                    }
            }
            else {
                Image(systemName: "bookmark")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ns.addBookmark(event)
                    }
            }
            
        }
        .foregroundColor(.gray)
            .padding(.trailing, 5)
            .font(.system(size: 14))
            .sheet(isPresented: $showingNewReply) {
                NewReply(replyTo: event)
                    .environmentObject(ns)
                    .environmentObject(up)
            }
    }
}

struct FooterFragment_Previews: PreviewProvider {
    static var previews: some View {
        
        let event7 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        if (event7 != nil) {
            FooterFragment(event: event7!)
                .withPreviewEnvironment()
        }
    }
}
