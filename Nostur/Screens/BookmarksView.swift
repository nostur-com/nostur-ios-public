
//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI

struct BookmarksContainer: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
//    @Environment(\.managedObjectContext) var viewContext
    
    init() {
        print("🧨🧨🧨🧨🧨 INIT BOOKMARKS CONTAINER 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
    }
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $nav.bookmarksPath) {
            VStack {
                if (ns.account != nil) {
                    BookmarksView(account: ns.account!)
                }
                else {
                    Text("Select account account first")
                }
            }
            .withNavigationDestinations()
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
                        Spacer()
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
                    .frame(width: 150)
//                    .background(.green)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
            }
            .padding(.horizontal)
            List {
                ForEach(bookmarks) { bookmark in
                    NoteRowView(event: bookmark)
                        .listRowInsets(EdgeInsets())
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.plain)
            Spacer()
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
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
        BookmarksContainer()
            .withPreviewEnvironment()
    }
}
