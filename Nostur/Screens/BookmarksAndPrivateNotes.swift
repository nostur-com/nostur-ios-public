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

    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Bookmarks" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    @AppStorage("selected_bookmarkssubtab") private var selectedSubTab = "Bookmarks"
    

    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var bookmarksCount:String?
    @State private var privateNotesCount:String?
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                HStack {
                    TabButton(action: {
                        selectedSubTab = "Bookmarks"
                    }, title: String(localized: "Bookmarks", comment: "Tab to switch to bookmarks"), secondaryText: bookmarksCount, selected: selectedSubTab == "Bookmarks")
                    
                    TabButton(action: {
                        selectedSubTab = "Private Notes"
                    }, title: String(localized: "Private Notes", comment: "Tab to switch to private notes"), secondaryText: privateNotesCount, selected: selectedSubTab == "Private Notes")
                }
                switch selectedSubTab {
                    case "Bookmarks":
                        BookmarksView(navPath: $navPath)
                    case "Private Notes":
                        PrivateNotesView(navPath: $navPath)
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
            .onPreferenceChange(BookmarksCountPreferenceKey.self, perform: { value in
                bookmarksCount = value == "0" ? nil : value
            })
            .onPreferenceChange(PrivateNotesCountPreferenceKey.self, perform: { value in
                privateNotesCount = value == "0" ? nil : value
            })
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
