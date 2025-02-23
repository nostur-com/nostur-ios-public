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

struct BookmarksView: View {
    @ObservedObject var vm: BookmarksFeedModel
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var ns: NRState
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_bookmarkssubtab") ?? "Bookmarks" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_bookmarkssubtab") }
    }
    
    @Binding public var navPath: NBNavigationPath
    
    @ObservedObject private var settings: SettingsStore = .shared

    @State private var bookmarkSnapshot: Int = 0
    @State private var didLoad = false

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            if !vm.nrLazyBookmarks.isEmpty {
                List {
                    Section {
                        ForEach(vm.filteredNrLazyBookmarks) { nrLazyBookmark in
                            ZStack { // Without this ZStack wrapper the bookmark list crashes on load ¯\_(ツ)_/¯{
                                LazyBookmark(nrLazyBookmark: nrLazyBookmark)
                            }
                            .id(nrLazyBookmark.id) // <-- must use .id or can't .scrollTo
                            .listRowSeparator(.hidden)
                            .listRowBackground(themes.theme.listBackground)
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .padding(.top, GUTTER)
                        }
                        .onDelete { indexSet in
                            deleteBookmark(section: vm.nrLazyBookmarks, offsets: indexSet)
                        }
                    } header: {
                        
                        SearchBox(prompt: String(localized: "Search in bookmarks...", comment: "Placeholder text in bookmarks search input box"), text: $vm.searchText, autoFocus: false)
                                .listRowSeparator(.hidden)
                                .listRowBackground(themes.theme.listBackground)
                                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .padding(.horizontal, 10)
                             
                    }
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
                .toolbar {
                    EditButton()
                }
                .padding(0)
                
                .preference(key: BookmarksCountPreferenceKey.self, value: vm.nrLazyBookmarks.count.description)
                .onReceive(receiveNotification(.didTapTab)) { notification in
                    guard selectedSubTab == "Bookmarks", let first = vm.nrLazyBookmarks.first else { return }
                    if !vm.nrLazyBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo(first.id)
                            }
                        }
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedSubTab == "Bookmarks", let first = vm.nrLazyBookmarks.first else { return }
                    if !vm.nrLazyBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo(first.id)
                            }
                        }
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedSubTab == "Bookmarks", let first = vm.nrLazyBookmarks.first else { return }
                    if !vm.nrLazyBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo(first.id)
                            }
                        }
                    }
                }
            }
            else {
                Text("When you bookmark a post it will show up here.")
                    .hCentered()
                    .padding(.top, 40)
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
            vm.load()
        })
    }
    
    private func deleteBookmark(section: [NRLazyBookmark], offsets: IndexSet) {
        withAnimation {
            vm.nrLazyBookmarks.remove(atOffsets: offsets)
        }
        // Delete from db
        for index in offsets {
            let bookmark = section[index]
            let bgContext = bg()
            bgContext.perform {
                Bookmark.removeBookmark(eventId: bookmark.id, context: bgContext)
                try? bgContext.save()
            }
        }
    }
}

#Preview("Bookmarks") {
    PreviewContainer({ pe in
        pe.loadPosts()
        pe.loadBookmarks()
    }) {
        VStack {
            BookmarksView(vm: BookmarksFeedModel(), navPath: .constant(NBNavigationPath()))
        }
    }
}


struct BookmarksCountPreferenceKey: PreferenceKey {
    static var defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
struct PrivateNotesCountPreferenceKey: PreferenceKey {
    static var defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}


struct LazyBookmark: View {
    
    @EnvironmentObject private var themes: Themes
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject public var nrLazyBookmark: NRLazyBookmark

    var body: some View {
        Box(nrPost: nrLazyBookmark.nrPost) {
            if let nrPost = nrLazyBookmark.nrPost {
                if nrPost.kind == 443 {
                    VStack {
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                        HStack(spacing: 0) {
                            self.replyButton
                                .foregroundColor(themes.theme.footerButtons)
                                .padding(.leading, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    navigateTo(nrPost)
                                }
                            Spacer()
                        }
                    }
                }
                else {
                    PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                }
            }
            else {
                ProgressView()
                    .frame(height: 175)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task {
                        bg().perform {
                            let nrPost = NRPost(event: nrLazyBookmark.bgEvent)
                            Task { @MainActor in
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

