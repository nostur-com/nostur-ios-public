//
//  Repost.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/09/2023.
//

import SwiftUI

struct Repost: View {
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.containerID) private var containerID
    @Environment(\.feedLayoutStabilizer) private var feedLayoutStabilizer
    @ObservedObject private var nrPost: NRPost
    @ObservedObject private var noteRowAttributes: NoteRowAttributes
    private var hideFooter = true // For rendering in NewReply
    private var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    private var connect: ThreadConnectDirection? = nil
    private let fullWidth: Bool
    private let isReply: Bool // is reply on PostDetail (needs 2*10 less box width)
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let grouped: Bool
    
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05)
    @State private var relayHint: String?
    @State private var revealMutedFirstQuoteByWords = false
    @State private var mutedWords: [String]
    @State private var displayedFirstQuote: NRPost?
//#if DEBUG
//    @State private var kind6Source: String?
//#endif
    
    init(nrPost: NRPost, hideFooter: Bool = false, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, fullWidth: Bool = false, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, grouped: Bool = false) {
        self.nrPost = nrPost
        self.noteRowAttributes = nrPost.noteRowAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        _mutedWords = State(initialValue: AppState.shared.bgAppState.mutedWords)
        _displayedFirstQuote = State(initialValue: nrPost.noteRowAttributes.firstQuote)
    }
    
    private var shouldForceAutoLoad: Bool { // To override auto download of the reposted post
        SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot)
    }
    
    var body: some View {
        Group {
            if isEmbedded {
                VStack(alignment: .leading, spacing: 6) {
                    RepostHeader(nrContact: nrPost.contact, nrPost: nrPost, embedded: true)
                    repostedPost(embedded: true)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 5)
                .background(
                    theme.listBackground
                        .cornerRadius(8)
                        .onTapGesture(perform: navigateToRepostedPost)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.lineColor, lineWidth: 1)
                )
                .clipped()
            }
            else {
                VStack(alignment: .leading) {
                    RepostHeader(nrContact: nrPost.contact)
                    repostedPost(embedded: false)
                }
            }
        }
        .task(id: nrPost.firstQuoteId) {
            guard noteRowAttributes.firstQuote == nil, nrPost.firstQuoteId != nil else { return }
            startFetchingFirstQuote()
        }
        .onReceive(receiveNotification(.mutedWordsChanged)) { _ in
            revealMutedFirstQuoteByWords = false
            mutedWords = AppState.shared.bgAppState.mutedWords
        }
        .onChange(of: noteRowAttributes.firstQuote?.id) { _ in
            guard let firstQuote = noteRowAttributes.firstQuote,
                  displayedFirstQuote?.id != firstQuote.id else { return }
            if let feedLayoutStabilizer {
                feedLayoutStabilizer.performAnchored(reason: "repost row resolved") {
                    displayedFirstQuote = firstQuote
                }
            } else {
                displayedFirstQuote = firstQuote
            }
        }
        .onAppear {
            if displayedFirstQuote == nil, let firstQuote = noteRowAttributes.firstQuote {
                displayedFirstQuote = firstQuote
            }
            self.enqueue()
        }
        .onDisappear { self.dequeue() }
    }

    private var resolvedFirstQuote: NRPost? {
        displayedFirstQuote ?? noteRowAttributes.firstQuote
    }

    private var didFailToFetchFirstQuote: Bool {
        switch vm.state {
        case .timeout, .error: return true
        default: return false
        }
    }

    @ViewBuilder
    private func repostedPost(embedded: Bool) -> some View {
        if let firstQuote = resolvedFirstQuote {
            if firstQuote.blocked || firstQuote.muted || (!notMutedWords(in: firstQuote.plainText, mutedWords: mutedWords) && !revealMutedFirstQuoteByWords) {
                HStack {
                    if firstQuote.blocked {
                        Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                    }
                    else if firstQuote.muted {
                        Text("_Muted post hidden_", comment: "Message shown when a post is muted")
                    }
                    else {
                        Text("_Muted post hidden_", comment: "Message shown when a quoted post is hidden because it matches muted words")
                    }
                    Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) {
                        nrPost.unblockFirstQuote()
                        nrPost.unmuteFirstQuote()
                        revealMutedFirstQuoteByWords = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.leading, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .hCentered()
            }
            else {
                KindResolver(nrPost: firstQuote, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: true, isReply: isReply, isDetail: isDetail, isEmbedded: embedded, connect: connect, forceAutoload: shouldForceAutoLoad)
                    .environment(\.repostMenuTarget, nrPost)
                    .padding(.horizontal, !embedded && firstQuote.kind == 30023 ? 10 : 0)
            }
        }
        else if nrPost.firstQuoteId == nil {
            Text("Reposted post unavailable")
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.lineColor, lineWidth: 1)
                )
        }
        else if didFailToFetchFirstQuote {
            VStack(spacing: 8) {
                Text("Unable to fetch reposted post")
                    .foregroundStyle(.secondary)
                Text("Retry")
                    .foregroundStyle(theme.accent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(perform: retryFetchingFirstQuote)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.lineColor, lineWidth: 1)
            )
        }
        else {
            theme.background
                .frame(height: embedded ? 120 : 250)
                .overlay { CenteredProgressView() }
        }
    }

    private func startFetchingFirstQuote() {
        guard let firstQuoteId = nrPost.firstQuoteId else { return }
        let fetchParams: FetchVM.FetchParams = (
            prio: true,
            req: { taskId in
                bg().perform { // 1. CHECK LOCAL DB
                    if let event = Event.fetchEvent(id: firstQuoteId, context: bg()) {
                        let nrFirstQuote = NRPost(event: event, withFooter: false)
                        Task { @MainActor in
                            noteRowAttributes.firstQuote = nrFirstQuote
                        }
                    }
                    else { // 2. ELSE CHECK RELAY
                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteRow.001")
                        req(RM.getEvent(id: firstQuoteId, subscriptionId: taskId))
                    }
                }
            },
            onComplete: { relayMessage, event in
                if let event = event, event.id == firstQuoteId {
                    let nrFirstQuote = NRPost(event: event, withFooter: false)
                    Task { @MainActor in
                        guard noteRowAttributes.firstQuote == nil else { return }
                        noteRowAttributes.firstQuote = nrFirstQuote
                    }
                }
                else if let event = Event.fetchEvent(id: firstQuoteId, context: bg()) {
#if DEBUG
                    if vm.state == .altLoading, let relay = self.relayHint {
                        L.og.debug("Event found on using relay hint: \(firstQuoteId) - \(relay)")
                    }
#endif
                    let nrFirstQuote = NRPost(event: event, withFooter: false)
                    Task { @MainActor in
                        guard noteRowAttributes.firstQuote == nil else { return }
                        noteRowAttributes.firstQuote = nrFirstQuote
                    }
                }
                else if (SettingsStore.shared.followRelayHints && vpnGuardOK()) && [.initializing, .loading].contains(vm.state) {
                    vm.altFetch()
                }
                else {
                    vm.timeout()
                }
            },
            altReq: { taskId in
                req(RM.getEvent(id: firstQuoteId, subscriptionId: taskId), relayType: .SEARCH)

                guard let relayHint = nrPost.fastTags.first(where: {
                    $0.0 == "e" && $0.1 == firstQuoteId && $0.2 != ""
                })?.2 else { return }

                self.relayHint = relayHint

#if DEBUG
                L.og.debug("FetchVM.3 HINT \(firstQuoteId) \(relayHint)")
#endif
                ConnectionPool.shared.sendEphemeralMessage(
                    RM.getEvent(id: firstQuoteId, subscriptionId: taskId),
                    relay: relayHint
                )
            }
        )
        vm.setFetchParams(fetchParams)
        vm.fetch()
    }
    
    private func enqueue() {
        if !nrPost.missingPs.isEmpty {
            bg().perform {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "Repost.001")
                QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
            }
        }
    }
    
    private func dequeue() {
        if !nrPost.missingPs.isEmpty {
            QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
        }
    }

    private func retryFetchingFirstQuote() {
        vm.state = .initializing
        startFetchingFirstQuote()
    }

    private func navigateToRepostedPost() {
        guard !nxViewingContext.contains(.preview) else { return }
        guard let firstQuote = noteRowAttributes.firstQuote else { return }
        navigateTo(firstQuote, context: containerID)
    }
}

struct RepostHeader: View {
    @Environment(\.containerID) private var containerID

    @ObservedObject public var nrContact: NRContact
    public var iconName: String = "arrow.2.squarepath"
    public var nrPost: NRPost? = nil
    public var embedded = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .fontWeightBold()
                .scaleEffect(0.6)
                .layoutPriority(1)
            
            PFP(pubkey: nrContact.pubkey, pictureUrl: nrContact.pictureUrl, size: 20.0)
            
            Text(nrContact.anyName)
                .lineLimit(1)
                .font(.subheadline)
                .fontWeightBold()
                .onTapGesture {
                    navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: containerID)
                }

            
            PossibleImposterLabelView(nrContact: nrContact)
                .layoutPriority(2)

            if let nrPost {
                Group {
                    Text(verbatim: "·")
                    Ago(nrPost.createdAt)
                        .equatable()
                    if let via = nrPost.via {
                        Text("· via \(via)")
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
        }
        .foregroundColor(.gray)
        .onTapGesture {
            navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: containerID)
        }
        .padding(.leading, embedded ? 0 : 30)
    }
}
