//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI
import Combine
import CoreData
import NavigationBackport

struct BookmarksScreen: View {
    @ObservedObject var vm: BookmarksFeedModel
    @Environment(\.theme) private var theme
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_bookmarkssubtab") ?? "Bookmarks" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_bookmarkssubtab") }
    }
    
    @Binding public var navPath: NBNavigationPath
    
    @ObservedObject private var settings: SettingsStore = .shared

    @State private var bookmarkSnapshot: Int = 0
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
                .onReceive(receiveNotification(.didTapTab)) { notification in
                    guard selectedSubTab == "Bookmarks"  && vm.nrLazyBookmarks.first != nil else { return }
                    if !vm.nrLazyBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo("top")
                            }
                        }
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedSubTab == "Bookmarks" && vm.nrLazyBookmarks.first != nil else { return }
                    if !vm.nrLazyBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo("top")
                            }
                        }
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedSubTab == "Bookmarks" && vm.nrLazyBookmarks.first != nil else { return }
                    if !vm.nrLazyBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo("top")
                            }
                        }
                    }
                }
            }
            else {
                Text("When you bookmark a post it will show up here.")
                    .centered()
                    .background(theme.listBackground)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            vm.load()
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
            vm.load()
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

#Preview("Bookmarks") {
    PreviewContainer({ pe in
        pe.loadPosts()
        pe.loadBookmarks()
    }) {
        VStack {
            BookmarksScreen(vm: BookmarksFeedModel(), navPath: .constant(NBNavigationPath()))
        }
    }
}


struct BookmarksCountPreferenceKey: PreferenceKey {
    static let defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
struct PrivateNotesCountPreferenceKey: PreferenceKey {
    static let defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}


struct LazyBookmark: View {
    
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @ObservedObject public var nrLazyBookmark: NRLazyBookmark
    public var fullWidth: Bool

    var body: some View {
        Box(nrPost: nrLazyBookmark.nrPost) {
            if let nrPost = nrLazyBookmark.nrPost {
                if nrPost.kind == 443 {
                    VStack {
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: fullWidth)
                        HStack(spacing: 0) {
                            self.replyButton
                                .foregroundColor(theme.footerButtons)
                                .padding(.leading, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    navigateTo(nrPost, context: containerID)
                                }
                            Spacer()
                        }
                    }
                }
                else {
                    PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: fullWidth)
                }
            }
            else {
                ProgressView()
                    .frame(height: 175)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onAppear {
                        bg().perform {
                            let nrPost = NRPost(event: nrLazyBookmark.bgEvent)
                            Task { @MainActor in
                                nrLazyBookmark.objectWillChange.send()
                                nrLazyBookmark.nrPost = nrPost
                            }
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    private var replyButton: some View {
        Image("ReplyIcon")
        Text("Comments")
    }
}

