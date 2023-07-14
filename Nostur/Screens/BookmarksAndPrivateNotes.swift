//
//  BookmarksAndPrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI

struct BookmarksAndPrivateNotes: View {
    
    @State var navPath = NavigationPath()
    @AppStorage("selected_tab") var selectedTab = "Bookmarks"
    @AppStorage("selected_bookmarkssubtab") var selectedSubTab = "Bookmarks"
    
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
                        BookmarksContainer()
                    case "Private Notes":
                        PrivateNotesContainer()
                    default:
                        Text("🥪")
                }
            }
            .padding(.top, 5)
            .withNavigationDestinations()
            .navigationTitle(selectedSubTab)
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard !IS_IPAD else { return }
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
