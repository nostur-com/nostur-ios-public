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
    
    @State private var nrPosts: [NRPost] = []
    @State private var message: String?
    @State private var prefetchedIds: Set<String> = []
    
    var body: some View {
        Container {
            if let message {
                Text(message)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .center)
            }
            else if nrPosts.isEmpty {
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
        }
        .task {
            do {
                _ = try await relayReq(Filters(authors: [pubkey], kinds: [10001]))
                
                let postIds: [String] = await withBgContext { _ in
                    Event.fetchReplacableEvent(10001, pubkey: pubkey)?.fastEs.map { $0.1 } ?? []
                }
                
                guard !postIds.isEmpty else {
                    message = "Nothing found"
                    return
                }
                
                _ = try await relayReq(Filters(ids: Set(postIds)))
                
                let nrPosts: [NRPost] = await withBgContext { bg in
                    Event.fetchEvents(postIds).map { NRPost(event: $0) }
                }
                
                Task { @MainActor in
                    self.nrPosts = nrPosts
                }
            }
            catch FetchError.timeout {
                self.message = "Nothing found"
            }
            catch {
                self.message = error.localizedDescription
            }
        }

    }
    
    func prefetch(_ post: NRPost) {
        guard SettingsStore.shared.fetchCounts else { return }
        guard !self.prefetchedIds.contains(post.id) else { return }
        guard let index = self.nrPosts.firstIndex(of: post) else { return }
        guard index % 5 == 0 else { return }
        
        let nextIds = self.nrPosts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
#if DEBUG
        L.fetching.info("🔢 Fetching counts for \(nextIds.count) posts")
#endif
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
}
