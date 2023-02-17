
//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI

struct BookmarksView: View {

    @Environment(\.managedObjectContext) var viewContext
    
    let account: Account?
    
    @FetchRequest(sortDescriptors: [])
    var bookmarks: FetchedResults<Event>
    
    init(account:Account? = nil) {
        self.account = account
        guard account != nil else { return }
        _bookmarks = FetchRequest(
            sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
            predicate: NSPredicate(format: "%@ IN bookmarkedBy", self.account!)
        )
    }
    
    var body: some View {
        VStack {
            // TODO: Account switcher/filter
            Text("Account: \(account?.display_name ?? account?.name ?? "No account")")
            Text("Your list of bookmarks is not public")
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
                                UIPasteboard.general.string = bookmark.id!
                            } label: {
                                Label("Copy note id hex \(bookmark.id!))", systemImage: "doc.on.clipboard")
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
                        .padding(20)
                    Divider()
                }.onDelete(perform: deleteItems)
            }
            Spacer()
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
        
        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
        
        BookmarksView(account: account!)
            .withPreviewEnvironment()
    }
}
