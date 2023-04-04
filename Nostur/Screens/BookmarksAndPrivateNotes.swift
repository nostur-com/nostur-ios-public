//
//  BookmarksAndPrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//
import SwiftUI

struct BookmarksAndPrivateNotes: View {
    
    @EnvironmentObject var nav:NavigationModel
    @AppStorage("selected_bookmarkssubtab") var selectedSubTab = "Bookmarks"
    
    var body: some View {
        NavigationStack(path: $nav.bookmarksPath) {
            VStack {
                HStack {
                    TabButton(action: {
                        selectedSubTab = "Bookmarks"
                    }, title: "Bookmarks", selected: selectedSubTab == "Bookmarks")
                    
                    TabButton(action: {
                        selectedSubTab = "Private Notes"
                    }, title: "Private Notes", selected: selectedSubTab == "Private Notes")
                }
                ZStack {
                    BookmarksContainer()
                        .frame(maxWidth: 600)
                        .opacity(selectedSubTab == "Bookmarks" ? 1 : 0)

                    PrivateNotesContainer()
                        .frame(maxWidth: 600)
                        .opacity(selectedSubTab == "Private Notes" ? 1 : 0)
                }
                Spacer()
            }
            .padding(.top, 5)
            .withNavigationDestinations()
            .navigationTitle(selectedSubTab)
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
//            .background(Color("ListBackground"))
        }
    }
}

struct BookmarksAndPrivateNotes_Previews: PreviewProvider {
    static var previews: some View {
        BookmarksAndPrivateNotes()
            .withPreviewEnvironment()
    }
}
