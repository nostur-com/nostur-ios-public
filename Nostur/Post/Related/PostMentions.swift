//
//  PostMentions.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/01/2026.


import SwiftUI
import NostrEssentials

// Copy paste from PostReposts/NotificationsReposts
struct PostMentions: View {
    
    public let id: String
    
    @Environment(\.containerID) private var containerID
    @Environment(\.theme) var theme
    
    @MainActor
    @State private var viewState: ViewState = .loading
    @State private var showNotWoT = false
    @State private var showBlocked = false
    
    var body: some View {
        Container {
            switch viewState {
            case .loading:
                CenteredProgressView()
                    .task(id: "quoted") {
                        viewState = await loadQuoted(id: id)
                    }
            case .ready(let nrPostsTuple):
                NXList(plain: true, showListRowSeparator: true) {
                    if nrPostsTuple.inWoT.isEmpty && nrPostsTuple.notWoT.isEmpty && nrPostsTuple.blocked.isEmpty {
                        ZStack(alignment: .center) {
                            theme.listBackground
                            VStack(spacing: 20) {
                                Text("Nothing here :(")
                                Button(action: {
                                    
                                }) {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                        .labelStyle(.iconOnly)
                                        .foregroundColor(theme.accent)
                                }
                            }
                        }
                    }
                    else {
                        ForEach(nrPostsTuple.inWoT) { nrPost in
                            Box(nrPost: nrPost) {
                                VStack(alignment: .leading, spacing: 0) {
                                    RepostHeader(nrContact: nrPost.contact, iconName: "quote.bubble.rtl")
                                        .offset(x: -35)
                                        .onAppear { self.enqueue(nrPost) }
                                        .onDisappear { self.dequeue(nrPost) }
                                    MinimalNoteTextRenderView(nrPost: nrPost, lineLimit: 5)
                                        .onTapGesture {
                                            navigateTo(nrPost, context: containerID)
                                        }
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                Ago(nrPost.createdAt).layoutPriority(2)
                                    .foregroundColor(.gray)
                                    .padding(10)
                            }
                            .id(nrPost.id)
                        }
                        
                        if WOT_FILTER_ENABLED() && !nrPostsTuple.notWoT.isEmpty && !showNotWoT {
                            Button {
                                showNotWoT = true
//                                Task { fetchMissingPs(nrPostsTuple.notWoT) }
                            } label: {
                                Text("Show more (\(nrPostsTuple.notWoT.count))")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(10)
                                    .contentShape(Rectangle())
                            }
                            .padding(.bottom, 10)
                        }
                        if showNotWoT {
                            ForEach(nrPostsTuple.notWoT) { nrPost in
                                Box(nrPost: nrPost) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        RepostHeader(nrContact: nrPost.contact, iconName: "quote.bubble.rtl")
                                            .offset(x: -35)
                                            .onAppear { self.enqueue(nrPost) }
                                            .onDisappear { self.dequeue(nrPost) }
                                        MinimalNoteTextRenderView(nrPost: nrPost, lineLimit: 5)
                                            .onTapGesture {
                                                navigateTo(nrPost, context: containerID)
                                            }
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    Ago(nrPost.createdAt).layoutPriority(2)
                                        .foregroundColor(.gray)
                                        .padding(10)
                                }
                                .id(nrPost.id)
                            }
                        }
                        
                        if !nrPostsTuple.blocked.isEmpty && !showBlocked {
                            Button {
                                showBlocked = true
//                                Task { fetchMissingPs(contactsTuple.blocked) }
                            } label: {
                                Text("Show blocked (\(nrPostsTuple.blocked.count))")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(10)
                                    .contentShape(Rectangle())
                            }
                            .padding(.bottom, 10)
                        }
                        
                        if showBlocked {
                            ForEach(nrPostsTuple.blocked) { nrPost in
                                Box(nrPost: nrPost) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        RepostHeader(nrContact: nrPost.contact, iconName: "quote.bubble.rtl")
                                            .offset(x: -35)
                                            .onAppear { self.enqueue(nrPost) }
                                            .onDisappear { self.dequeue(nrPost) }
                                        MinimalNoteTextRenderView(nrPost: nrPost, lineLimit: 5)
                                            .onTapGesture {
                                                navigateTo(nrPost, context: containerID)
                                            }
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    Ago(nrPost.createdAt).layoutPriority(2)
                                        .foregroundColor(.gray)
                                        .padding(10)
                                }
                                .id(nrPost.id)
                            }
                        }
                    }
                }
            case .error(let message):
                Text(message ?? "Error")
                    .centered()
            }
        }

        .onReceive(  ViewUpdates.shared.relatedUpdates
            .filter { $0.type == .Reposts && $0.eventId == self.id }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main), perform: { _ in
                Task {
                    viewState = await loadQuoted(id: id)
                }
        })
        
        .navigationTitle("Mentioned by")
    }
    
    private func loadQuoted(id: String) async -> ViewState {
        _ = try? await relayReq(Filters(kinds: [1,1111,30023], tagFilter: TagFilter(tag: "q", values: [id])), timeout: 5.5)
        
        // Get reposts, return related contact
        let (mentionsCount, nrPostsTuple): (Int64, ([NRPost], [NRPost], [NRPost])) = await withBgContext { bg in
            let blocked = blocks()
            let mentions = Event.fetchMentions(id: id)
            
            let oldTypeMentions = Event.fetchEventsBy(firstQuoteId: id, andKinds: Set(SUPPORTED_KINDS_CAN_HAVE_MENTIONS.map(\.self.id)), context: bg)
            
            let mentionsCount = Int64(mentions.count + oldTypeMentions.count)
            
            if let mentionedEvent = Event.fetchEvent(id: self.id, context: bg) {
                mentionedEvent.mentionsCount = mentionsCount
            }
            
            return (mentionsCount, (
                (mentions + oldTypeMentions).filter { $0.inWoT && !blocked.contains($0.pubkey) }
                    .map { NRPost(event: $0) },
                (mentions + oldTypeMentions).filter { !$0.inWoT && !blocked.contains($0.pubkey) }
                    .map { NRPost(event: $0) },
                (mentions + oldTypeMentions).filter { blocked.contains($0.pubkey) }
                    .map { NRPost(event: $0) }
            ))
        }
        
        defer {
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: id, mentions: mentionsCount))
        }
        return ViewState.ready(nrPostsTuple)
    }
    
    private func enqueue(_ nrPost: NRPost) {
        if !nrPost.missingPs.isEmpty {
            bg().perform {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostMentions.001")
                QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
            }
        }
    }
    
    private func dequeue(_ nrPost: NRPost) {
        if !nrPost.missingPs.isEmpty {
            QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
        }
    }
}

extension PostMentions {
    enum ViewState {
        case loading
        case ready((inWoT: [NRPost], notWoT: [NRPost], blocked: [NRPost])) // inWoT, notInWoT, blocked
        case error(String?)
    }
}

#Preview {
    PostMentions(id: "e94ac42f1f09ae06fa7b7eaaee199e29d6c45537308a198f89cad91624f999a2")
}

