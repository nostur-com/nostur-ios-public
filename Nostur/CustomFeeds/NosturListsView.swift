//
//  NosturListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2023.
//

import SwiftUI
import NavigationBackport

struct NosturListsView: View {
    @EnvironmentObject private var themes:Themes
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath:\CloudFeed.createdAt, ascending: false)])
    var lists:FetchedResults<CloudFeed>
    
    @State var confirmDeleteShown = false
    @State var listToDelete:CloudFeed? = nil
    @State var newListSheet = false
    @State private var didRemoveDuplicates = false
        
    var body: some View {
        VStack {
            if !lists.isEmpty {
                List(lists) { list in
                    NBNavigationLink(value: list) {
                        ListRow(list: list)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    listToDelete = list
                                    confirmDeleteShown = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                            }
                    }
                    .listRowBackground(themes.theme.background)
                }
                .scrollContentBackgroundCompat(.hidden)
                .background(themes.theme.listBackground)
                .onReceive(lists.publisher.collect()) { lists in
                    if !didRemoveDuplicates {
                        removeDuplicateLists()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(String(localized:"Create new feed", comment: "Button to create a new feed")) {
                    newListSheet = true
                }
            }
        }
        .navigationTitle(String(localized:"Feeds", comment: "Navigation title for Feeds screen"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete feed \(listToDelete?.name ?? "")", isPresented: $confirmDeleteShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let listToDelete = listToDelete else { return }
                viewContext.delete(listToDelete)
                DataProvider.shared().save()
                self.listToDelete = nil
            }
        }
        .sheet(isPresented: $newListSheet) {
            NBNavigationStack {
                NewListSheet()
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.background)
        }
    }
    
    func removeDuplicateLists() {
        var uniqueLists = Set<String>()
        let sortedLists = lists.sorted {
            if ($0.showAsTab && !$1.showAsTab) { return true }
            else {
                return ($0.createdAt as Date?) ?? Date.distantPast > ($1.createdAt as Date?) ?? Date.distantPast
            }
        }
        
        sortedLists.forEach { feed in
            print("feed: \(feed.id?.uuidString ?? "?") \(feed.name_)")
        }
        
        
        let duplicates = sortedLists
            .filter { list in
                guard let id = list.id else { return false }
                return !uniqueLists.insert(id.uuidString).inserted
            }
        
        duplicates.forEach {
            DataProvider.shared().viewContext.delete($0)
        }
        if !duplicates.isEmpty {
            L.cloud.debug("Deleting: \(duplicates.count) duplicate feeds")
            DataProvider.shared().save()
            didRemoveDuplicates = true
        }
    }
}

struct ListRow: View {
    @ObservedObject var list:CloudFeed
    let showPin:Bool
    
    init(list: CloudFeed, showPin:Bool = true) {
        self.list = list
        self.showPin = showPin
    }
    
    var body: some View {
        HStack {
            if showPin {
                Image(systemName: list.showAsTab ? "pin.fill" : "pin")
            }
            Text(list.name_)
            Spacer()
        }
    }
}

struct NosturListsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
        }) {
            NBNavigationStack {
                NosturListsView()
                    .withNavigationDestinations()
            }
        }
    }
}
