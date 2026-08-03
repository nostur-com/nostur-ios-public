//
//  PostAndParent.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI
import NostrEssentials

// Renders reply, and parent
// the parent is another PostAndParent
// so it recursively renders up to the root
struct PostAndParent: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.containerID) private var containerID
    @Environment(\.theme) private var theme
    @ObservedObject private var nrPost: NRPost
    
    private var navTitleHidden: Bool = false
    
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + DIMENSIONS.POST_PFP_SPACE
    
    @ObservedObject private var settings: SettingsStore = .shared
    @State private var timerTask: Task<Void, Never>?
    @State private var didLoad = false
    @State private var didFetchParent = false
    @State private var parentLookupTimedOut = false
    @State private var locallyResolvedReplyToRoot: NRPost? = nil
    
    init(nrPost: NRPost, navTitleHidden: Bool = false, connect: ThreadConnectDirection? = nil) {
        self.nrPost = nrPost
        self.navTitleHidden = navTitleHidden
        self.connect = connect
    }
    
    var body: some View {
//#if DEBUG
//        let _ = nxLogChanges(of: Self.self)
//#endif
        VStack(spacing: 0) {
            // MARK: PARENT POST WITH POTENTIALLY ANOTHER PARENT
            // We have the event: replyTo_ = already .replyTo or lazy fetched with .replyToId/.zappedEventId
            if let replyTo = nrPost.replyTo {
                if replyTo.deletedById == nil {
                    let connect:ThreadConnectDirection? = replyTo.replyToPostOrZapId != nil ? .both : .bottom
                    PostAndParent(nrPost: replyTo, connect: connect)
                        .environment(\.nxViewingContext, [.selectableText, .postParent, .detailPane])
                        .padding(.bottom, isPicturePost(replyTo) ? 0 : 10)
                        .background(theme.listBackground)
                    if isPicturePost(replyTo) {
                        Divider()
                            .padding(.bottom, 24)
                    }
                }
                else {
                    Text("_Deleted by author_", comment: "Message shown when a post is deleted")
                        .hCentered()
                    Button("Undelete") {
                        nrPost.objectWillChange.send()
                        replyTo.undelete()
                    }
                    .foregroundColor(theme.accent)
                    .hCentered()
                }
            }
            else if let replyToPostOrZapId = nrPost.replyToPostOrZapId {
                Group {
                    if let replyToRoot = distinctReplyToRoot(from: replyToPostOrZapId) {
                        PostAndParent(nrPost: replyToRoot, connect: .bottom)
                            .environment(\.nxViewingContext, [.selectableText, .postParent, .detailPane])
                            .padding(.bottom, 10)
                            .background(theme.listBackground)
                    }

                    if parentLookupTimedOut {
                        missingReplyConnector
                    }
                    else {
                        CenteredProgressView()
                    }
                }
                .onAppear {
                    startParentLookup(replyToPostOrZapId)
                }
                .background(theme.listBackground)
                .onDisappear {
                    timerTask?.cancel()
                    timerTask = nil
                }
            }
            // MARK: A POST 
            VStack(alignment: .leading, spacing: 0) {
                if nxViewingContext.contains(.postParent) {
                    PostRowDeletable(nrPost: nrPost, hideFooter: true, connect: postParentConnect, theme: theme)
                        .environment(\.nxViewingContext, [.selectableText, .postParent, .detailPane])
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                        .background(
                            theme.listBackground
                                .onTapGesture {
                                    guard !nxViewingContext.contains(.preview) else { return }
                                    navigateTo(nrPost, context: containerID)
                                }
                        )
                        .padding(.bottom, 10)
                }
                else {
                    PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToPostOrZapId != nil && nrPost.replyTo == nil, connect: detailConnect, fullWidth: true, isDetail: true, theme: theme)
                        .environment(\.nxViewingContext, [.selectableText, .postDetail, .detailPane])
//                        .id(nrPost.id)
//                        .padding(.top, 10) // So the focused post is not glued to top after scroll, so you can still see .replyTo connecting line
                        .padding(.bottom, 10)
                        .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
                        
                }
            }
            .onAppear {
               guard nrPost.replyToPostOrZapId != nil else { return } // don't scroll if we already the root
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
                    
                    if (!nxViewingContext.contains(.postParent)) {
                        
                        fetchDetailStuff(
                            kind: Int(nrPost.kind),
                            pTags: Set(nrPost.fastTags.filter { $0.0 == "p" }.map { $0.1 }),
                            rootE: nrPost.id,
                            nrPost: nrPost
                        )
                        Task {
                            await fetchMentions()
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

    private var detailConnect: ThreadConnectDirection? {
        guard nrPost.replyToPostOrZapId != nil else { return nil }
        guard let replyTo = nrPost.replyTo, isPicturePost(replyTo) else { return .top }
        return nil
    }

    private var postParentConnect: ThreadConnectDirection? {
        guard let replyTo = nrPost.replyTo, isPicturePost(replyTo) else { return connect }

        switch connect {
        case .both:
            return .bottom
        case .top:
            return nil
        case .bottom, .none:
            return connect
        }
    }

    private func isPicturePost(_ post: NRPost) -> Bool {
        post.kind == 20 || (post.kind == 1 && post.kTag == "20")
    }
    
    @ViewBuilder
    private var replyButton: some View {
        Image("ReplyIcon")
        Text("Add comment")
    }

    @ViewBuilder
    private var missingReplyConnector: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: 44)

            Text(String(localized: "Earlier replies are unavailable.", comment: "Shown between a thread root and a visible reply when intermediate private or missing replies cannot be fetched"))
                .foregroundColor(theme.secondary)

            Spacer(minLength: 0)

            Button(String(localized: "Try to fetch", comment: "Button to retry fetching a missing reply in a thread")) {
                retryParentLookup()
            }
            .buttonStyle(.plain)
            .foregroundColor(theme.accent)
            .disabled(nxViewingContext.contains(.preview))
        }
        .font(.footnote)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: 0.5, y: 0))
                    path.addLine(to: CGPoint(x: 0.5, y: geometry.size.height))
                }
                .stroke(
                    theme.lineColor,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
            .frame(width: 1)
            .offset(x: THREAD_LINE_OFFSET)
        }
        .accessibilityElement(children: .combine)
    }

    private func distinctReplyToRoot(from replyToPostOrZapId: String) -> NRPost? {
        guard nrPost.replyToRootId != replyToPostOrZapId else { return nil }
        return nrPost.replyToRoot ?? locallyResolvedReplyToRoot
    }

    private func startParentLookup(_ replyToPostOrZapId: String) {
        guard !didFetchParent else { return }
        didFetchParent = true
        parentLookupTimedOut = false

        bg().perform {
            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.001")
        }

        enqueueReference(replyToPostOrZapId)
        if let replyToRootId = nrPost.replyToRootId, replyToRootId != replyToPostOrZapId {
            resolveReplyToRootFromLocalStorage(replyToRootId)
            enqueueReference(replyToRootId)
        }

        timerTask?.cancel()
        timerTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(2.25) * NSEC_PER_SEC)
                nrPost.loadReplyTo()

                guard nrPost.replyTo == nil else { return }
                searchForReference(replyToPostOrZapId)
                if let replyToRootId = nrPost.replyToRootId, replyToRootId != replyToPostOrZapId, nrPost.replyToRoot == nil {
                    searchForReference(replyToRootId)
                }

                try await Task.sleep(nanoseconds: UInt64(4) * NSEC_PER_SEC)
                nrPost.loadReplyTo()
                if nrPost.replyTo == nil {
                    if let replyToRootId = nrPost.replyToRootId, replyToRootId != replyToPostOrZapId {
                        resolveReplyToRootFromLocalStorage(replyToRootId)
                    }
                    parentLookupTimedOut = true
                }
            }
            catch { }
        }
    }

    private func retryParentLookup() {
        timerTask?.cancel()
        timerTask = nil
        didFetchParent = false
        if let replyToPostOrZapId = nrPost.replyToPostOrZapId {
            startParentLookup(replyToPostOrZapId)
        }
    }

    private func enqueueReference(_ reference: String) {
        if reference.count > 64 && reference.contains(":") {
            QueuedFetcher.shared.enqueue(aTag: reference)
        }
        else {
            QueuedFetcher.shared.enqueue(id: reference)
        }
    }

    private func resolveReplyToRootFromLocalStorage(_ replyToRootId: String) {
        let bgContext = bg()
        bgContext.perform {
            let rootEvent: Event? = if replyToRootId.contains(":") {
                Event.fetchReplacableEvent(aTag: replyToRootId, context: bgContext)
            }
            else {
                Event.fetchEvent(id: replyToRootId, context: bgContext)
            }

            guard let rootEvent else { return }
            let rootPost = NRPost(event: rootEvent, withReplyTo: true)
            DispatchQueue.main.async {
                guard nrPost.replyToRootId == replyToRootId else { return }
                locallyResolvedReplyToRoot = rootPost
            }
        }
    }

    private func searchForReference(_ reference: String) {
        if reference.count > 64 && reference.contains(":"), let aTag = try? ATag(reference) {
            req(RM.getArticle(pubkey: aTag.pubkey, kind: Int(aTag.kind), definition: aTag.definition))
        }
        else {
            req(RM.getEvent(id: reference), relayType: .SEARCH)
        }

        if vpnGuardOK() {
            fetchEventFromRelayHint(reference, fastTags: nrPost.fastTags)
        }
    }
    
    private func fetchMentions() async {
        guard SUPPORTED_KINDS_CAN_HAVE_MENTIONS.map(\.self.id).contains(Int(nrPost.kind)) else { return }
        
        _ = try? await relayReq(Filters(kinds: [1,1111,30023], tagFilter: TagFilter(tag: "q", values: [nrPost.id])), timeout: 3.0)
        
        // Get reposts, return related contact
        let mentionsCount: Int64 = await withBgContext { bg in
            Event.fetchMentionsCount(id: nrPost.id, context: bg)
        }
        
        Task { @MainActor in
            nrPost.footerAttributes.mentionsCount = mentionsCount
        }
    }
}


func fetchDetailStuff(kind: Int, pTags: Set<String> = [], rootE: String? = nil, rootA: String? = nil, nrPost: NRPost? = nil) {
    // NEW NIP-22:
    if NIP22_ROOT_KINDS.contains(kind) {
        // Fetch p (0)
        if !pTags.isEmpty {
            QueuedFetcher.shared.enqueue(pTags: pTags)
        }
        
        if let rootE {
            // Fetch E direct or sub 1111,1244 (new commments style)
            nxReq(
                Filters(
                    kinds: [1111,1244],
                    tagFilter: TagFilter(tag: "E", values: [rootE]),
                    limit: 500
                ),
                subscriptionId: "DETAIL-"+UUID().uuidString
            )
            
            // Fetch E direct or sub 1111,1244 (new commments style) - REAL TIME UPDATES
            nxReq(
                Filters(
                    kinds: [1111,1244],
                    tagFilter: TagFilter(tag: "E", values: [rootE]),
                    since: NTimestamp(date: Date.now).timestamp
                ),
                subscriptionId: "REALTIME-DETAIL-22"
            )
            
            // Fetch e direct or sub 1 (old replies style) - REAL TIME UPDATES
            nxReq(
                Filters(
                    kinds: [1],
                    tagFilter: TagFilter(tag: "e", values: [rootE]),
                    since: NTimestamp(date: Date.now).timestamp
                ),
                subscriptionId: "REALTIME-DETAIL"
            )
            
            // Fetch e direct or sub comments (1) (old style)
            nxReq(
                Filters(
                    kinds: [1],
                    tagFilter: TagFilter(tag: "e", values: [rootE]),
                    limit: 500
                ),
                subscriptionId: "DETAIL-"+UUID().uuidString
            )
        }
        
        
    }
    else if let nrPost {
        
        // OLD NIP-10 ETC:
        
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
            if replyToRootId.contains(":") {
                req(RM.getPREventReferences(aTag: replyToRootId, subscriptionId: "ROOT-"+UUID().uuidString, kinds:[1]))
            }
            else {
                req(RM.getEventReferences(ids: [replyToRootId], subscriptionId: "ROOT-"+UUID().uuidString, kinds:[1]))
            }
        }
    }
}



#Preview("Debug more text button missing") {
    PreviewContainer({ pe in
        pe.parseEventJSON([
            ###"{"content":"The latest https://github.com/fiatjaf/nak release (v0.16.2) comes with an --outbox flag to \"nak req\", which means you don't have to specify relays in your filter and relays from specific authors will be used (filters will be smartly split).\n\nWhich means you can, for example, get all pubkeys who have published to wss://lang.relays.land/es then go to each of their own outbox relay, fetch their new notes live and publish those to wss://lang.relays.land/es.\n\nnak req -l 10000 lang.relays.land/es | jq --slurp 'map(.pubkey) | unique | {authors: .}' | nak req --since '1 hour ago' -k 1 --outbox -n 3 --stream | nak event lang.relays.land/es","created_at":1757341689,"tags":[["client","jumble"]],"kind":1,"sig":"331866685cfdb505d1bd51c2601272f3c88d87174f723a4714e603cee56de0fbf7944b8db853d7599c323844c49128d100716e8cbadbe87d8068d7a4dbe56930","id":"66a7dacb40f4892b9f70b931588f38143a55c42c36c1547c894c83a828f750e5","pubkey":"3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"}"###,
            ###"{"sig":"a2d3516795fc6aea14f9481032ebdde6e4ea9faea3708f21f45afbb79bf5b293605a21d3811e3d0730c63b2c21b072baa1d878adc00f6e5b628dfaebe4e848a4","id":"a9d1686e1c1663fc077a3be3c0f608fd68ebc11f827f350e286908593f8899fe","pubkey":"d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e","content":"Very cool. Is this the first time you have implemented the outbox model yourself?","tags":[["e","66a7dacb40f4892b9f70b931588f38143a55c42c36c1547c894c83a828f750e5","wss://relay.damus.io/","root","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],["e","66a7dacb40f4892b9f70b931588f38143a55c42c36c1547c894c83a828f750e5","wss://relay.damus.io/","reply","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],["p","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"]],"kind":1,"created_at":1757350228}"###,
            ###"{"id":"c51120aef05ebfb4422afbb2a54a37f3e07564279c7be29d9c8ed5a802f3d611","created_at":1757359520,"tags":[["e","66a7dacb40f4892b9f70b931588f38143a55c42c36c1547c894c83a828f750e5","wss://relay.damus.io/","root","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],["e","a9d1686e1c1663fc077a3be3c0f608fd68ebc11f827f350e286908593f8899fe","wss://relay.damus.io/","reply","d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"],["p","d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"],["client","jumble"]],"pubkey":"3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d","kind":1,"content":"I am not sure what it means to \"implement the outbox model\", but if you're talking about whatever code that talks directly to people's relays I've implemented it a bunch of different ways in different places, and this is really just a few lines based on code that already existed in the Go library.","sig":"550440667a284966e075659505d6b105ce689cf60e9fac77787f3d146a7ed77d207678eca42fa2b090a5970235d150369519cb0f58f971c22051221170ee2e47"}"###
        ])
    }) {
        if let post1 = PreviewFetcher.fetchNRPost("c51120aef05ebfb4422afbb2a54a37f3e07564279c7be29d9c8ed5a802f3d611") {
            
            PostDetailView(nrPost: post1)
            
        }
    }
}
