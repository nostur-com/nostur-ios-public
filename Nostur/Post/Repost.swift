//
//  Repost.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/09/2023.
//

import SwiftUI

struct Repost: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @ObservedObject private var nrPost: NRPost
    @ObservedObject private var noteRowAttributes: NoteRowAttributes
    private var hideFooter = true // For rendering in NewReply
    private var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    private var connect: ThreadConnectDirection? = nil
    private let fullWidth: Bool
    private let isReply: Bool // is reply on PostDetail (needs 2*10 less box width)
    private let isDetail: Bool
    private let grouped: Bool
    private var theme: Theme
    
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05)
    @State private var relayHint: String?
//#if DEBUG
//    @State private var kind6Source: String?
//#endif
    
    init(nrPost: NRPost, hideFooter: Bool = false, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, fullWidth: Bool = false, isReply: Bool = false, isDetail: Bool = false, grouped: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.noteRowAttributes = nrPost.noteRowAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
        self.theme = theme
    }
    
    private var shouldForceAutoLoad: Bool { // To override auto download of the reposted post
        SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            RepostHeader(pfpAttributes: nrPost.pfpAttributes)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
            
            if let firstQuote = noteRowAttributes.firstQuote {
                // CASE - WE HAVE REPOSTED POST ALREADY
                if firstQuote.blocked {
                    HStack {
                        Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                        Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) {
                            nrPost.unblockFirstQuote()
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
                    KindResolver(nrPost: firstQuote, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: true, isReply: isReply, isDetail: isDetail, connect: connect, forceAutoload: shouldForceAutoLoad, theme: theme)

                    // Extra padding reposted long form, because normal repost/post has 10, but longform uses 20
                    // so add the extra 10 here
                        .padding(.horizontal, firstQuote.kind == 30023 ? 10 : 0)
                }
            }
            else {
                theme.background
                    .frame(height: 475)
            }
        }
        .overlay {
            if let firstQuoteId = nrPost.firstQuoteId, noteRowAttributes.firstQuote == nil {
                CenteredProgressView()
                    .onBecomingVisible {
                        let fetchParams: FetchVM.FetchParams = (
                            prio: true,
                            req: { taskId in
                                bg().perform { // 1. CHECK LOCAL DB
                                    if let event = Event.fetchEvent(id: firstQuoteId, context: bg()) {
                                        let nrFirstQuote = NRPost(event: event, withFooter: false)
                                        Task { @MainActor in
                                            noteRowAttributes.firstQuote = nrFirstQuote // Maybe not need this? handled in nrPost?
                                        }
                                    }
                                    else { // 2. ELSE CHECK RELAY
                                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteRow.001")
                                        req(RM.getEvent(id: firstQuoteId, subscriptionId: taskId))
                                    }
                                }
                            },
                            onComplete: { relayMessage, event in
                                if let event = event {
                                    let nrFirstQuote = NRPost(event: event, withFooter: false)
                                    Task { @MainActor in
                                        guard noteRowAttributes.firstQuote == nil else { return }
                                        noteRowAttributes.firstQuote = nrFirstQuote
                                    }
                                }
                                else if let event = Event.fetchEvent(id: firstQuoteId, context: bg()) { // 3. WE FOUND IT ON RELAY
                                    if vm.state == .altLoading, let relay = self.relayHint {
                                        L.og.debug("Event found on using relay hint: \(firstQuoteId) - \(relay)")
                                    }
                                    let nrFirstQuote = NRPost(event: event, withFooter: false)
                                    Task { @MainActor in
                                        guard noteRowAttributes.firstQuote == nil else { return }
                                        noteRowAttributes.firstQuote = nrFirstQuote
                                    }
                                }
                                // Still don't have the event? try to fetch from relay hint
                                // TODO: Should try a relay we don't already have in our relay set
                                else if (SettingsStore.shared.followRelayHints && vpnGuardOK()) && [.initializing, .loading].contains(vm.state) {
                                    // try search relays and relay hint
                                    vm.altFetch()
                                }
                                else { // 5. TIMEOUT
                                    vm.timeout()
                                }
                            },
                            altReq: { taskId in // IF WE HAVE A RELAY HINT WE USE THIS REQ, TRIGGERED BY vm.altFetch()
                                // Try search relays
                                req(RM.getEvent(id: firstQuoteId, subscriptionId: taskId), relayType: .SEARCH)
                                guard let relayHint = nrPost.fastTags.first(where: {
                                    $0.0 == "e" && $0.1 == firstQuoteId && $0.2 != ""
                                })?.2 else { return }
                                self.relayHint = relayHint
                                
                                L.og.debug("FetchVM.3 HINT \(firstQuoteId) \(relayHint)")
                                ConnectionPool.shared.sendEphemeralMessage(
                                    RM.getEvent(id: firstQuoteId, subscriptionId: taskId),
                                    relay: relayHint
                                )
                            }
                            
                        )
                        vm.setFetchParams(fetchParams)
                        vm.fetch()
                    }
            }
        }
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
}

struct RepostHeader: View {
    @EnvironmentObject private var dim: DIMENSIONS

    @ObservedObject public var pfpAttributes: PFPAttributes
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.2.squarepath")
                .fontWeightBold()
                .scaleEffect(0.6)
                .layoutPriority(1)
            
            PFP(pubkey: pfpAttributes.pubkey, pictureUrl: pfpAttributes.pfpURL, size: 20.0)
            
            Group {
                Text(pfpAttributes.anyName)
                Text("reposted")
                    .layoutPriority(1)
            }
            .font(.subheadline)
            .fontWeightBold()
            .onTapGesture {
                navigateToContact(pubkey: pfpAttributes.pubkey, pfpAttributes: pfpAttributes, context: dim.id)
            }
            
            PossibleImposterLabelView(pfp: pfpAttributes)
                .layoutPriority(2)
        }
        .foregroundColor(.gray)
        .onTapGesture {
            navigateToContact(pubkey: pfpAttributes.pubkey, pfpAttributes: pfpAttributes, context: dim.id)
        }
        .padding(.leading, 30)
    }
}
