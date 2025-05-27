//
//  PostAndParent.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI

// Renders reply, and parent
// the parent is another PostAndParent
// so it recursively renders up to the root
struct PostAndParent: View {
    @ObservedObject private var themes: Themes = .default
    @ObservedObject private var nrPost: NRPost
    @EnvironmentObject private var dim: DIMENSIONS
    
    private var navTitleHidden: Bool = false
    
    private var isParent = false
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + DIMENSIONS.POST_PFP_SPACE
    
    @ObservedObject private var settings: SettingsStore = .shared
    @State private var timerTask: Task<Void, Never>?
    @State private var didLoad = false
    @State private var didFetchParent = false
    
    init(nrPost: NRPost, isParent: Bool = false, navTitleHidden: Bool = false, connect: ThreadConnectDirection? = nil) {
        self.nrPost = nrPost
        self.isParent = isParent
        self.navTitleHidden = navTitleHidden
        self.connect = connect
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing: 10) {
            // MARK: PARENT NOTE
            // We have the event: replyTo_ = already .replyTo or lazy fetched with .replyToId
            if let replyTo = nrPost.replyTo {
                if replyTo.deletedById == nil {
                    let connect:ThreadConnectDirection? = replyTo.replyToId != nil ? .both : .bottom
                    PostAndParent(nrPost: replyTo, isParent: true, connect: connect)
//                            .padding(10)
                        .background(themes.theme.listBackground)
                }
                else {
                    Text("_Deleted by author_", comment: "Message shown when a post is deleted")
                        .hCentered()
                    Button("Undelete") {
                        nrPost.objectWillChange.send()
                        replyTo.undelete()
                    }
                    .foregroundColor(themes.theme.accent)
                    .hCentered()
                }
            }
            else if let replyToId = nrPost.replyToId {
                CenteredProgressView()
                    .onBecomingVisible {
                        guard !didFetchParent else { return }
                        didFetchParent = true
                        
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.001")
                        }
                        QueuedFetcher.shared.enqueue(id: replyToId)
                        
                        timerTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(2.25) * NSEC_PER_SEC)
                                if nrPost.replyTo == nil {
                                    // try search relays
                                    req(RM.getEvent(id: replyToId), relayType: .SEARCH)
                                    
                                    // try relay hint
                                    guard vpnGuardOK() else { return }
                                    fetchEventFromRelayHint(replyToId, fastTags: nrPost.fastTags)
                                }
                            }
                            catch { }
                        }
                    }
                    .background(themes.theme.listBackground)
                    .onDisappear {
                        timerTask?.cancel()
                        timerTask = nil
                    }
            }
            // OUR (DETAIL) REPLY:
            // MARK: DETAIL NOTE
            VStack(alignment: .leading, spacing: 0) {
                if isParent {
                    PostRowDeletable(nrPost: nrPost, hideFooter: true, connect: connect)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                        .background(
                            themes.theme.listBackground
                                .onTapGesture {
                                    navigateTo(nrPost, context: dim.id)
                                }
                        )
                }
                else {
                    PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToId != nil && nrPost.replyTo == nil, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: true, isDetail: true, theme: themes.theme)
//                        .id(nrPost.id)
                        .padding(.top, 10) // So the focused post is not glued to top after scroll, so you can still see .replyTo connecting line
                        .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
                        
                }
            }
            .onAppear {
               guard nrPost.replyToId != nil else { return } // don't scroll if we already the root
               DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                   sendNotification(.scrollToDetail, nrPost.id)
               }
            }
            .id(nrPost.id)
            .onAppear {
                guard !nrPost.plainTextOnly else { L.og.debug("plaintext enabled, probably spam") ; return }
                guard !didLoad else { return }
                didLoad = true
                nrPost.loadReplyTo()
                nrPost.footerAttributes.loadFooter()
                
                bg().perform {
                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.003")
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                    }
                    
                    if (!isParent) {
                        
                        // Fetch all related (e and p.kind=0)
                        // (the events and contacts mentioned in this DETAIL NOTE.
                        if let message = RequestMessage.getFastTags(nrPost.fastTags) {
                            req(message)
                        }
                        
                        // Fetch all that reference this detail note (Replies, zaps, reactions)
                        req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "DETAIL-"+UUID().uuidString))
                        // REAL TIME UPDATES FOR POST DETAIL
                        req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL", since: NTimestamp(date: Date.now)))
                        
                        if let replyToRootId = nrPost.replyToRootId {
                            // Fetch all that reference the root note
                            // to build the thread, maybe kind=1 is enough, or all...?
                            req(RM.getEventReferences(ids: [replyToRootId], subscriptionId: "ROOT-"+UUID().uuidString, kinds:[1]))
                        }
                    }
                }
            }
            .onDisappear {
                bg().perform {
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var replyButton: some View {
        Image("ReplyIcon")
        Text("Add comment")
    }
}
