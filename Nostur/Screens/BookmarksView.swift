
//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI

struct BookmarksW: View {
    @EnvironmentObject var ns:NosturState
//    @Environment(\.managedObjectContext) var viewContext
    
    var body: some View {
        let _ = Self._printChanges()
        if (ns.account != nil) {
            BookmarksView(account: ns.account!)
        }
        else {
            Text("Select account account first")
        }
    }
}

struct BookmarksView: View {

    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    let account: Account
    
    @FetchRequest(sortDescriptors: [])
    var bookmarks: FetchedResults<Event>
    
    @State var selectedAccount:Account? = nil
    
    init(account:Account) {
        print("🧨🧨🧨🧨🧨 INIT BOOKMARKS VIEW 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
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
                    ForEach(ns.accounts) { account in
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
                        ZStack {
                            if (selectedAccount != nil) {
                                ProfilePicView(pubkey: selectedAccount!.publicKey, account: selectedAccount, size: 30)
                            }
                            else {
                                ForEach(ns.accounts.indices, id:\.self) { index in
                                    ProfilePicView(pubkey: ns.accounts[index].publicKey, account: ns.accounts[index], size: 30)
                                        .offset(x: -CGFloat(index*10))
                                    
                                }
                            }
                        }
                    }
                    .frame(width: 60)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
            }
            .padding(.horizontal)
            ScrollView {
                ForEach(bookmarks) { bookmark in
                    NoteRowView(event: bookmark)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = bookmark.noteId
                            } label: {
                                Label("Copy note id \(bookmark.noteId)", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                UIPasteboard.general.string = bookmark.id
                            } label: {
                                Label("Copy note id hex \(bookmark.id))", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                print("Unfollow @\(bookmark.username)")
                            } label: {
                                Label("Unfollow @\(bookmark.username)", systemImage: "person.fill.xmark")
                            }
                            Button {
                                print("Block @\(bookmark.username)")
                            } label: {
                                Label("Block @\(bookmark.username)", systemImage: "slash.circle")
                            }
                        }
                        .padding(.horizontal)
                    Divider()
                }.onDelete(perform: deleteItems)
            }
            Spacer()
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
//        .navigationBarHidden(true)
        .padding()
        .onChange(of: selectedAccount) { newValue in
            if (newValue != nil) {
                bookmarks.nsPredicate = NSPredicate(format: "%@ IN bookmarkedBy", newValue!)
            }
            else {
                bookmarks.nsPredicate = NSPredicate(format: "bookmarkedBy.@count > 0")
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { bookmarks[$0] }.forEach(viewContext.delete)
            do { try viewContext.save() } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct BookmarksView_Previews: PreviewProvider {
    static var previews: some View {
        BookmarksW()
            .withPreviewEnvironment()
    }
}
