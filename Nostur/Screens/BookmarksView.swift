
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
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
     
    
    let account: Account
    
    @FetchRequest(sortDescriptors: [])
    var bookmarks: FetchedResults<Event>
    
    var vBookmarks:[VPost] {
        bookmarks.compactMap { VPostTransformer.shared.toVPost($0, skipParents: true) }
    }
    
    var accounts:[Account] {
        ns.accounts.filter { $0.privateKey != nil }
    }
    
    @ObservedObject var settings:SettingsStore = .shared
    @State var selectedAccount:Account? = nil
    @State var viewNeedsUpdate = false
    
    init(account:Account) {
        self.account = account
        self.selectedAccount = account
        _bookmarks = FetchRequest(
            sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
            predicate: NSPredicate(format: "bookmarkedBy.@count > 0")
        )
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
                    //                    .background(.green)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
            }
            .padding(.horizontal)
            ScrollView {
                LazyVStack {
                    ForEach(vBookmarks) { vBookmark in
                        NoteRow(vPost: vBookmark)
                            .background(Color.systemBackground)
                            .boxShadow()
                            .padding(.vertical, 10)
                            .padding(.horizontal, settings.fullWidthImages ? 0 : 10)
                            .id(vBookmark.id)
                            .onTapGesture {
                                navigateTo(vBookmark)
                            }
                            .onDelete {
                                vBookmark.event.bookmarkedBy = []
                                Task.detached {
                                    DataProvider.shared().save()
                                }
                            }
                    }
                }
            }
            Spacer()
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
//        .padding()
//        .background(Color("ListBackground"))
        .onReceive(receiveNotification(.viewNeedsUpdate), perform: { _ in
            if (selectedAccount != nil) {
                bookmarks.nsPredicate = NSPredicate(format: "%@ IN bookmarkedBy", selectedAccount!)
            }
            else {
                bookmarks.nsPredicate = NSPredicate(format: "bookmarkedBy.@count > 0")
            }
            viewNeedsUpdate.toggle()
        })
        .onChange(of: selectedAccount) { newValue in
            if (newValue != nil) {
                bookmarks.nsPredicate = NSPredicate(format: "%@ IN bookmarkedBy", newValue!)
            }
            else {
                bookmarks.nsPredicate = NSPredicate(format: "bookmarkedBy.@count > 0")
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
