//
//  BookmarksAndPrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI
import NavigationBackport

struct BookmarksTab: View {
    @StateObject private var bookmarksVM = BookmarksFeedModel()
    @EnvironmentObject private var fa: LoggedInAccount
    @Environment(\.theme) private var theme
    @State private var navPath = NBNavigationPath()

    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Bookmarks" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    @AppStorage("selected_bookmarkssubtab") private var selectedSubTab = "Bookmarks"
    

    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var bookmarksCount: String?
    @State private var privateNotesCount: String?
    @State private var showBookmarkFilterOptions = false
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        NBNavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                HStack {
                    TabButton(
                        action: { selectedSubTab = "Bookmarks" },
                        title: String(localized: "Bookmarks", comment: "Tab to switch to bookmarks"),
                        secondaryText: bookmarksCount,
                        selected: selectedSubTab == "Bookmarks",
                        tools: {
                            Image(systemName: bookmarksVM.bookmarkFilters.count < 5 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .padding(.leading, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showBookmarkFilterOptions = true
                                }
                        }
                    )
                    
                    TabButton(action: {
                        selectedSubTab = "Private Notes"
                    }, title: String(localized: "Private Notes", comment: "Tab to switch to private notes"), secondaryText: privateNotesCount, selected: selectedSubTab == "Private Notes")
                }
                ZStack {
                    theme.listBackground
                    
                    AvailableWidthContainer {
                        switch selectedSubTab {
                            case "Bookmarks":
                                BookmarksScreen(vm: bookmarksVM, navPath: $navPath)
                            case "Private Notes":
                                PrivateNotesScreen(navPath: $navPath)
                            default:
                                Text("🥪")
                        }
                    }
                    .padding(.top, GUTTER)
                }
                AudioOnlyBarSpace()
            }
            .background(theme.listBackground) // screen / toolbar background
            .nosturNavBgCompat(theme: theme) // <-- Needs to be inside navigation stack
            .withNavigationDestinations()
            .navigationTitle(selectedSubTab)
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard !IS_IPAD || horizontalSizeClass == .compact else { return }
                guard selectedTab == "Bookmarks" else { return }
                navPath.append(destination.destination)
            }
            .onReceive(receiveNotification(.clearNavigation)) { notification in
                navPath.removeLast(navPath.count)
            }
            .onPreferenceChange(BookmarksCountPreferenceKey.self, perform: { value in
                bookmarksCount = value == "0" ? nil : value
            })
            .onPreferenceChange(PrivateNotesCountPreferenceKey.self, perform: { value in
                privateNotesCount = value == "0" ? nil : value
            })
            .sheet(isPresented: $showBookmarkFilterOptions, onDismiss: {
                showBookmarkFilterOptions = false
            }, content: {
                NBNavigationStack {
                    BookmarkFilters(onlyShow: $bookmarksVM.bookmarkFilters)
                        .environment(\.theme, theme)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(theme.background)
                .presentationDetents200()
            })
            
            .tabBarSpaceCompat()
        }
        .nbUseNavigationStack(.never)
    }
}

struct BookmarksAndPrivateNotes_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadBookmarks()
            pe.loadPrivateNotes()
        }) {
            BookmarksTab()
        }
    }
}
