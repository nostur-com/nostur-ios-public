//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI

struct BookmarksContainer: View {
    @EnvironmentObject var ns:NosturState

    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing:0) {
            if (ns.account != nil) {
                BookmarksView(account: ns.account!)
            }
            else {
                Text("Select account first")
            }
        }
    }
}

struct BookmarksView: View {

    @EnvironmentObject var ns:NosturState

    let account: Account
    @State var vBookmarks:[NRPost] = []

    var accounts:[Account] {
        ns.accounts.filter { $0.privateKey != nil }
    }

    @ObservedObject var settings:SettingsStore = .shared
    @State var selectedAccount:Account? = nil


    init(account:Account) {
        self.account = account
        self.selectedAccount = account
    }

    var body: some View {
//        let _ = Self._printChanges()
        ScrollView {
            if !vBookmarks.isEmpty {
                LazyVStack {
                    ForEach(vBookmarks) { vBookmark in
                        PostRowDeletable(nrPost: vBookmark, missingReplyTo: true)
                            .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                            .fixedSize(horizontal: false, vertical: true)
                            .roundedBoxShadow()
                            .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                            .id(vBookmark.id)
                            .onDelete {
                                vBookmarks = vBookmarks.filter { $0.id != vBookmark.id }
                                
                                DataProvider.shared().bg.perform {
                                    vBookmark.event.bookmarkedBy = []
                                    DataProvider.shared().bgSave()
                                }
                            }
                    }
                    Spacer()
                }
                .background(Color("ListBackground"))
            }
            else {
                Text("When you bookmark a post it will show up here.")
                    .hCentered()
                    .padding(.top, 40)
            }
        }
        .overlay(alignment:.topTrailing) {
            AccountSwitcher(accounts: accounts, selectedAccount: $selectedAccount)
                .padding(.horizontal)
        }
        .onReceive(receiveNotification(.postAction)) { notification in
            let action = notification.object as! PostActionNotification
            if (action.type == .bookmark  && !action.bookmarked) {
                vBookmarks = vBookmarks.filter { $0.id != action.eventId }
            }
            else if action.type == .bookmark {
                self.loadBookmarks()
            }
        }
        .navigationTitle(String(localized:"Bookmarks", comment:"Navigation title for Bookmarks screen"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .onChange(of: selectedAccount) { account in
            self.loadBookmarks(forAccount: account)
        }
        .task {
            self.loadBookmarks()
        }
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
    
    func loadBookmarks(forAccount account: Account? = nil) {
        let fr = Event.fetchRequest()
        if let account {
            fr.predicate = NSPredicate(format: "%@ IN bookmarkedBy", account)
        }
        else {
            fr.predicate = NSPredicate(format: "bookmarkedBy.@count > 0")
        }
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        let ctx = DataProvider.shared().bg
        ctx.perform {
            if let bookmarks = try? ctx.fetch(fr) {
                self.vBookmarks = bookmarks.map { NRPost(event: $0) }
            }
        }
    }
}

struct BookmarksView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
            pe.loadBookmarks()
        }) {
            VStack {
                BookmarksContainer()
            }
        }
    }
}
