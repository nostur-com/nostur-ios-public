//
//  BookmarksAndPrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI

struct BookmarksAndPrivateNotes: View {
    @EnvironmentObject private var fa:LoggedInAccount
    @EnvironmentObject private var themes:Themes
    @State private var navPath = NavigationPath()
    @AppStorage("selected_tab") private var selectedTab = "Bookmarks"
    @AppStorage("selected_bookmarkssubtab") private var selectedSubTab = "Bookmarks"
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                HStack {
                    TabButton(action: {
                        selectedSubTab = "Bookmarks"
                    }, title: String(localized: "Bookmarks", comment: "Tab to switch to bookmarks"), selected: selectedSubTab == "Bookmarks")
                    
                    TabButton(action: {
                        selectedSubTab = "Private Notes"
                    }, title: String(localized: "Private Notes", comment: "Tab to switch to private notes"), selected: selectedSubTab == "Private Notes")
                }
                switch selectedSubTab {
                    case "Bookmarks":
                        BookmarksView(account: fa.account, navPath: $navPath)
                    case "Private Notes":
                        PrivateNotesView(account: fa.account, navPath: $navPath)
                    default:
                        Text("🥪")
                }
            }
            .background(themes.theme.listBackground)
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
        }
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
            BookmarksAndPrivateNotes()
        }
    }
}
