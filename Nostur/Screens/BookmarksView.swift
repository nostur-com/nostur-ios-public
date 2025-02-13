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
            if !vm.nrBookmarks.isEmpty {
                List {
                    ForEach (vm.nrBookmarks) { nrBookmark in
                        ZStack { // Without this ZStack wrapper the bookmark list crashes on load ¯\_(ツ)_/¯{
                            Box(nrPost: nrBookmark) {
                                PostRowDeletable(nrPost: nrBookmark, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                            }
                        }
                        .id(nrBookmark.id) // <-- must use .id or can't .scrollTo
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive, action: {
                                bg().perform {
                                    Bookmark.removeBookmark(eventId: nrBookmark.id, context: bg())
                                    bg().transactionAuthor = "removeBookmark"
                                    DataProvider.shared().save()
                                    bg().transactionAuthor = nil
                                }
                            }) {
                                Label("Remove", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(themes.theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .padding(.bottom, GUTTER)
                    }
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
                .padding(0)
                
                .preference(key: BookmarksCountPreferenceKey.self, value: vm.nrBookmarks.count.description)
                .onReceive(receiveNotification(.didTapTab)) { notification in
                    guard selectedSubTab == "Bookmarks", let first = vm.nrBookmarks.first else { return }
                    if !vm.nrBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo(first.id)
                            }
                        }
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedSubTab == "Bookmarks", let first = vm.nrBookmarks.first else { return }
                    if !vm.nrBookmarks.isEmpty {
                        if navPath.count == 0 {
                            withAnimation {
                                proxy.scrollTo(first.id)
                            }
                        }
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedSubTab == "Bookmarks", let first = vm.nrBookmarks.first else { return }
                    if !vm.nrBookmarks.isEmpty {
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
        
        .simultaneousGesture(
            DragGesture().onChanged({
                if 0 < $0.translation.height {
                    sendNotification(.scrollingUp)
                }
                else if 0 > $0.translation.height {
                    sendNotification(.scrollingDown)
                }
            }))
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
