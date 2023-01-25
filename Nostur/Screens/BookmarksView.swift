//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI

struct BookmarksView: View {
    
    @EnvironmentObject var accountState:AccountState

    @State var bookmarks:[Event]?
    
    var body: some View {
        
        
        if bookmarks != nil {
            ScrollView {
                ForEach(bookmarks!, id:\.self) { bookmark in
                    NoteRowView(event: bookmark)
                }
                Spacer()
            }
        }
        else if (bookmarks?.count == 0) {
            Text("You don't have any bookmarks")
        }
        else {
            Text("You don't have any bookmarks")
                .onAppear {
                    if bookmarks == nil {
                        if (accountState.activeAccount()?.bookmarks != nil) {
                            bookmarks = Array((accountState.activeAccount()?.bookmarks)!)
                        }
                    }
                }
        }
        
    }
}

struct BookmarksView_Previews: PreviewProvider {
    static var previews: some View {
        BookmarksView()
            .withPreviewEnvironment()
    }
}
