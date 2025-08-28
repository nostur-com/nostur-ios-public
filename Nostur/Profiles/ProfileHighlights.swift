//
//  ProfileHighlights.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/08/2025.
//

import SwiftUI
import NostrEssentials

struct ProfileHighlights: View {
    @ObservedObject private var settings: SettingsStore = .shared
    
    public let pubkey: String
    
    @State private var viewState: ViewState = .loading
    @State private var prefetchedIds: Set<String> = []
    
    enum ViewState {
        case loading
        case posts([NRPost])
        case error(String)
    }
    
    var body: some View {
        switch viewState {
        case .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .center)
                .task {
                    await load()
                }
        case .posts(let nrPosts):
            if nrPosts.isEmpty {
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .center)
            }
            else {
                ForEach(nrPosts) { nrPost in
                    ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                        Box(nrPost: nrPost) {
                            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, ignoreBlock: true)
                        }
                    }
                    .onBecomingVisible {
                        prefetch(nrPost)
                    }
                    .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                }
            }
        case .error(let message):
            Text(message)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .center)
        }
    }
    
    private func load() async {
        _ = try? await relayReq(Filters(authors: [pubkey], kinds: [10001]), timeout: 5.5)
        
        let postIds: [String] = await withBgContext { _ in
            Event.fetchReplacableEvent(10001, pubkey: pubkey)?.fastEs.map { $0.1 } ?? []
        }
        
        guard !postIds.isEmpty else {
            viewState = .error("Nothing found")
            return
        }
        
        _ = try? await relayReq(Filters(ids: Set(postIds)), timeout: 2.5)
        
        let nrPosts: [NRPost] = await withBgContext { bg in
            Event.fetchEvents(postIds)
                .filter { $0.pubkey == pubkey } // make sure pubkey matches
                .map { NRPost(event: $0) }
        }
        
        Task { @MainActor in
            viewState = .posts(nrPosts)
        }
    }
    
    private func prefetch(_ post: NRPost) {
        guard SettingsStore.shared.fetchCounts else { return }
        guard !self.prefetchedIds.contains(post.id) else { return }
        
        if case let .posts(nrPosts) = viewState {
            guard let index = nrPosts.firstIndex(of: post) else { return }
            guard index % 5 == 0 else { return }
            
            let nextIds = nrPosts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
            guard !nextIds.isEmpty else { return }
#if DEBUG
            L.fetching.info("🔢 Fetching counts for \(nextIds.count) posts")
#endif
            fetchStuffForLastAddedNotes(ids: nextIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
        }
    }
    
}
