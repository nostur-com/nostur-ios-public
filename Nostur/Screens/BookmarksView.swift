
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
        let _ = Self._printChanges()
        VStack {
            if (ns.account != nil) {
                BookmarksView(account: ns.account!)
            }
            else {
                Text("Select account account first")
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
        let _ = Self._printChanges()
        VStack {
            HStack {
                Spacer()
                Menu {
                    Button {
                        selectedAccount = nil
                    } label: {
                        HStack {
                            Text("All accounts")
                            Spacer()
                        }
                    }
                    ForEach(accounts) { account in
                        Button {
                            selectedAccount = account
                        } label: {
                            HStack {
                                //                            ProfilePicView(pubkey: account.publicKey, account: account, size: 30)
                                Text("@\(account.name)")
                                Spacer()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        ZStack {
                            if (selectedAccount != nil) {
                                PFP(pubkey: selectedAccount!.publicKey, pictureUrl: selectedAccount?.picture, size: 30, isFollowing: true)
                            }
                            else {
                                ForEach(accounts.indices, id:\.self) { index in
                                    PFP(pubkey: accounts[index].publicKey, pictureUrl: accounts[index].picture, size: 30, isFollowing: true)
                                        .offset(x: -CGFloat(index*10))

                                }
                            }
                        }
                    }
                    .frame(width: 150)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
            }
            .padding(.horizontal)
            ScrollView {
                LazyVStack {
                    ForEach(vBookmarks) { vBookmark in
                        PostRowDeletable(nrPost: vBookmark)
                            .background(Color.systemBackground)
                            .boxShadow()
                            .padding(.vertical, 10)
                            .padding(.horizontal, settings.fullWidthImages ? 0 : 10)
                            .id(vBookmark.id)
                            .onDelete {
                                vBookmark.mainEvent.bookmarkedBy = []
                                vBookmarks = vBookmarks.filter { $0.id != vBookmark.id }
                                    DataProvider.shared().save()
                            }
                    }
                }
            }
            Spacer()
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
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .onChange(of: selectedAccount) { account in
            self.loadBookmarks(forAccount: account)
        }
        .task {
            self.loadBookmarks()
        }
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
        BookmarksContainer()
            .withPreviewEnvironment()
    }
}
