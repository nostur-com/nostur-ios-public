//
//  BookmarksColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/11/2025.
//

import SwiftUI

struct BookmarksColumn: View {
    public let filters: ActiveBookmarkFilters
    @StateObject var vm = BookmarksColumnVM()
    @Environment(\.theme) private var theme
    
    @ObservedObject private var settings: SettingsStore = .shared
    
    @State private var didLoad = false
    @State private var lastDeleted: String? = nil

    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        ScrollViewReader { proxy in
            if vm.isLoading {
                CenteredProgressView()
                    .background(theme.listBackground)
            }
            else if !vm.nrLazyBookmarks.isEmpty {
                List {
                    SearchBox(prompt: String(localized: "Search in bookmarks...", comment: "Placeholder text in bookmarks search input box"), text: $vm.searchText, autoFocus: false)
                        .id("top")
                        .listRowSeparator(.hidden)
                        .listRowBackground(theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    
                    ForEach(vm.filteredNrLazyBookmarks) { nrLazyBookmark in
                        LazyBookmark(nrLazyBookmark: nrLazyBookmark, fullWidth: settings.fullWidthImages)
                        .listRowSeparator(.hidden)
                        .listRowBackground(theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .padding(.bottom, GUTTER)
                        
                    }
                    .onDelete { indexSet in
                        deleteBookmark(section: vm.filteredNrLazyBookmarks, offsets: indexSet)
                    }
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
//                .toolbar {
//                    EditButton()
//                }
                .padding(0)
                
                .preference(key: BookmarksCountPreferenceKey.self, value: vm.nrLazyBookmarks.count.description)
            }
            else {
                Text("When you bookmark a post it will show up here.")
                    .centered()
                    .background(theme.listBackground)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            vm.load(filters: filters)
            didLoad = true
        }
        .navigationTitle(String(localized:"Bookmarks", comment:"Navigation title for Bookmarks screen"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .onReceive(ViewUpdates.shared.bookmarkUpdates, perform: { update in
            if let lastDeleted, lastDeleted == update.id { // don't reload if we already removed with deleteBookmark() (swipe) or bookmark button toggle (tap)
                return
            }
            // should only reload when delete from external or different screen
            vm.load(filters: filters)
        })
        
        .onReceive(receiveNotification(.postAction)) { notification in
            // Used when tapping on bookmark icon to remove
            // Removes from screen directly and doesn't do flicker reload again at db update from ViewUpdates.shared.bookmarkUpdates because
            // we set lastDeleted
            let postAction = notification.object as! PostActionNotification
            if case .bookmark(_) = postAction.type, postAction.bookmarked == false {
                // Set lastDeleted so screen doesn't flicker/reload
                lastDeleted = postAction.eventId
                withAnimation { // just update with nice animation
                    vm.nrLazyBookmarks.removeAll(where: { $0.id == postAction.eventId })
                }
            }
            
        }
    }
    
    private func deleteBookmark(section: [NRLazyBookmark], offsets: IndexSet) {
        
        let bookmarkIdsToDelete = section.indices
            .filter { offsets.contains($0) }
            .map { section[$0] }.map { $0.id }
        
        withAnimation { // just update with nice animation
            vm.nrLazyBookmarks.removeAll(where: { bookmarkIdsToDelete.contains($0.id) })
        }
        
        // Set lastDeleted so screen doesn't flicker/reload
        for bookmarkId in bookmarkIdsToDelete {
            lastDeleted = bookmarkId
        }
        
        // Delete from db
        let bgContext = bg()
        bgContext.perform {
            for bookmarkId in bookmarkIdsToDelete {
                Bookmark.removeBookmark(eventId: bookmarkId, context: bgContext)
            }
            try? bgContext.save()
        }
    }
}

#Preview {
    BookmarksColumn(filters: ActiveBookmarkFilters(filters: []))
}

