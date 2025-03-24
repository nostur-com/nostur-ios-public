//
//  ThreadReplies.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/05/2023.
//

import SwiftUI

struct ThreadReplies: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject public var nrPost: NRPost
    @State private var timer:Timer? = nil
    @State private var showNotWoT = false
    @State private var didLoad = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        LazyVStack(spacing: GUTTER) {
            if didLoad {
                ForEach(nrPost.groupedRepliesSorted) { reply in
                    PostOrThread(nrPost: reply, rootId: nrPost.id)
                        .id(reply.id)
                        .animation(Animation.spring(), value: nrPost.groupedRepliesSorted)
                }
                if !nrPost.groupedRepliesNotWoT.isEmpty {
                    Divider()
                    if WOT_FILTER_ENABLED() && !showNotWoT {
                        Button {
                            showNotWoT = true
                        } label: {
                           Text("Show more")
                                .padding(10)
                                .contentShape(Rectangle())
                        }
                        .padding(.bottom, 10)
                    }
                    if showNotWoT {
                        ForEach(nrPost.groupedRepliesNotWoT) { reply in
                            PostOrThread(nrPost: reply, rootId: nrPost.id)
                                .id(reply.id)
                        }
                        .animation(Animation.spring(), value: nrPost.groupedRepliesNotWoT)
                    }
                }
                // If there are less than 5 replies, put some empty space so our detail note is at top of screen
    //            if (nrPost.replies.count < 5) {
    //                themes.theme.listBackground.frame(height: 400)
    //            }
    //            Spacer()
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            guard !didLoad else { return }
            guard !nrPost.plainTextOnly else { L.og.debug("plaintext enabled, probably spam") ; return }
            nrPost.loadGroupedReplies()
            didLoad = true
            
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

import NavigationBackport

#Preview("Grouped replies") {
    let exampleId = "2e7119c8135375060ab0f3e40646869f7337ab86de32574ab1bf57dcd2a93754"
    
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let nrPost = PreviewFetcher.fetchNRPost(exampleId, withReplies: true) {
                ScrollView {
                    ThreadReplies(nrPost: nrPost)
                }
            }
        }
    }
}
