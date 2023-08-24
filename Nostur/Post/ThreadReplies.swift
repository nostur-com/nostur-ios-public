//
//  ThreadReplies.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/05/2023.
//

import SwiftUI

struct ThreadReplies: View {
    @ObservedObject var nrPost:NRPost
    @EnvironmentObject var ns:NosturState
    @State var timer:Timer? = nil
    @State var showNotWoT = false
    
    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(nrPost.groupedRepliesSorted.prefix(50)) { reply in
                PostOrThread(nrPost: reply, grouped:true, rootId: nrPost.id)
                    .id(nrPost.id)
            }
            .animation(Animation.spring(), value: nrPost.groupedRepliesSorted)
            if !nrPost.groupedRepliesNotWoT.isEmpty {
                Divider()
                if WOT_FILTER_ENABLED() && !showNotWoT {
                    Button("Show more") {
                        showNotWoT = true
                    }
                }
                if showNotWoT {
                    ForEach(nrPost.groupedRepliesNotWoT.prefix(50)) { reply in
                        PostOrThread(nrPost: reply, grouped:true, rootId: nrPost.id)
                            .id(nrPost.id)
                    }
                    .animation(Animation.spring(), value: nrPost.groupedRepliesNotWoT)
                }
            }
            // If there are less than 5 replies, put some empty space so our detail note is at top of screen
            if (nrPost.replies.count < 5) {
                Rectangle().frame(height: 400)
                    .background(Color("ListBackground"))
                    .foregroundColor(Color("ListBackground"))
            }
            Spacer()
        }
        .background(nrPost.replies.isEmpty ? Color.systemBackground : Color("ListBackground"))
        .onAppear {
            guard !nrPost.plainTextOnly else { L.og.info("plaintext enabled, probably spam") ; return }
            nrPost.loadGroupedReplies()
            
            // After many attempts, still some replyTo's are missing, somewhere some observable is not
            // triggering, cant find out where. So use this workaround...
//            timer?.invalidate()
//            timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false, block: { _ in
//                nrPost.loadGroupedReplies()
//            })
        }
        .onReceive(receiveNotification(.blockListUpdated)) { _ in
            nrPost.loadGroupedReplies()
        }
        .onReceive(receiveNotification(.muteListUpdated)) { _ in
            nrPost.loadGroupedReplies()
        }
    }
        
}

struct ThreadReplies2_Previews: PreviewProvider {
    static var previews: some View {
        
        let exampleId = "2e7119c8135375060ab0f3e40646869f7337ab86de32574ab1bf57dcd2a93754"
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NavigationStack {
                if let example = PreviewFetcher.fetchEvent(exampleId) {
                    let nrPost = NRPost(event: example, withReplyTo: false, withParents: false, withReplies: true, plainText: false)
                    ScrollView {
                        ThreadReplies(nrPost: nrPost)
                    }
                }
            }
        }
    }
}
